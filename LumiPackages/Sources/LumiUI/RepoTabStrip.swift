import LumiKit
import LumiState
import SwiftUI

import UniformTypeIdentifiers

/// Header tab şeridi: repo tab'leri + (+) butonu tek yatay ScrollView'da.
/// (+) her zaman son tab'ın HEMEN ardında durur. Şerit kalan tüm genişliği alır;
/// sığmayan tab'lar scroll'lanır ve aktif tab görünür alana kaydırılır.
/// Tab'lar sürükle-bırak ile yeniden sıralanır (canlı: üstünden geçilen tab'ın
/// yerine kayar); sıra `WorkspaceStore.moveTab` üzerinden persist edilir.
struct RepoTabStrip: View {
    let workspace: WorkspaceStore
    let repoStore: RepoStore

    @State private var isAddRepoHovering = false
    @State private var draggingTab: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(workspace.openTabs, id: \.self) { repoPath in
                        tabChip(repoPath)
                    }
                    addRepoButton
                }
            }
            .onChange(of: workspace.activeTab) { _, active in
                guard let active else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(active) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Şerit boşluğuna bırakılan sürükleme: durumu temizle (chip opaklığı geri gelir)
        .onDrop(of: [.plainText], isTargeted: nil) { _ in
            draggingTab = nil
            return true
        }
    }

    private func tabChip(_ repoPath: String) -> some View {
        RepoTabChip(
            name: repoStore.repo(at: repoPath)?.name
                ?? (repoPath as NSString).lastPathComponent,
            isActive: workspace.activeTab == repoPath,
            onSelect: { workspace.setActiveTab(repoPath) },
            onClose: { name in
                workspace.requestCloseTab(repoPath, repoName: name)
            }
        )
        .id(repoPath)
        .opacity(draggingTab == repoPath ? 0.4 : 1)
        .onDrag {
            draggingTab = repoPath
            return NSItemProvider(object: repoPath as NSString)
        }
        .onDrop(
            of: [.plainText],
            delegate: TabReorderDropDelegate(
                target: repoPath,
                dragging: $draggingTab,
                move: { workspace.moveTab($0, to: $1) }
            )
        )
    }

    private var addRepoButton: some View {
        Button {
            workspace.isRepoSelectorOpen.toggle()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isAddRepoHovering ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 32, height: 32)
                .background(isAddRepoHovering ? Theme.bgElevated : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isAddRepoHovering = $0 }
        .popover(isPresented: Binding(
            get: { workspace.isRepoSelectorOpen },
            set: { workspace.isRepoSelectorOpen = $0 }
        )) {
            RepoSelectorView(
                groups: repoStore.groupedRepos,
                openTabPaths: Set(workspace.openTabs),
                collapsedGroups: Binding(
                    get: { workspace.collapsedRepoGroups },
                    set: { workspace.collapsedRepoGroups = $0 }
                )
            ) { repo in
                workspace.isRepoSelectorOpen = false
                workspace.openTab(repo.path)
            }
        }
    }
}

/// Canlı yeniden sıralama: sürüklenen tab başka bir tab'ın üstüne girdiği anda
/// onun konumuna taşınır (bırakmayı beklemez). Drop tamamlanınca durum sıfırlanır.
private struct TabReorderDropDelegate: DropDelegate {
    let target: String
    @Binding var dragging: String?
    let move: (String, String) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        withAnimation(.easeInOut(duration: 0.15)) { move(dragging, target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Repo tab'i (v1 globals.css .repo-tab): pasif şeffaf, aktif elevated +
/// accent kenarlık; kapatma butonu yalnız hover'da görünür, hover'ı kırmızı.
struct RepoTabChip: View {
    let name: String
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: (String) -> Void

    @State private var isHovering = false
    @State private var isCloseHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 11))
            Text(name)
                .font(.system(size: 13, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 120, alignment: .leading)
            closeButton
                .opacity(isHovering || isActive ? 1 : 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .background(isActive ? Theme.bgElevated : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isActive ? Theme.accentVivid.opacity(0.25) : Color.clear,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(isActive ? Theme.accentPrimary : Theme.textSecondary)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }

    private var closeButton: some View {
        Button {
            onClose(name)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isCloseHovering ? Theme.error : Theme.textMuted)
                .frame(width: 18, height: 18)
                .background(isCloseHovering ? Theme.error.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isCloseHovering = $0 }
    }
}
