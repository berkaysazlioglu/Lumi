import LumiKit
import LumiState
import SwiftUI

/// Header tab şeridi: repo tab'leri + (+) butonu tek HStack'te. (+) her zaman
/// son tab'ın HEMEN ardında durur. Şerit kalan tüm genişliği alır; tab'lar
/// sığmazsa metinleri kısalarak daralır (ikon + kapatma her zaman görünür).
///
/// Bu view yalnız ÇİZER: chip frame'lerini (hosting koordinatı) modele yayınlar,
/// sürükleme offset'ini ve hover'ı modelden okur. Seçme / reorder / hover
/// etkileşimi `TabStripInteractionView`'da (AppKit, hosting dışı) — gerekçe
/// `TabStripInteractionModel`. ScrollView bilinçli olarak yok.
struct RepoTabStrip: View {
    let workspace: WorkspaceStore
    let repoStore: RepoStore
    let interaction: TabStripInteractionModel

    @State private var isAddRepoHovering = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(workspace.openTabs, id: \.self) { repoPath in
                tabChip(repoPath)
            }
            addRepoButton
                .fixedSize()
        }
        .onPreferenceChange(TabChipFramesKey.self) { frames in
            Task { @MainActor in interaction.chipFrames = frames }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tabChip(_ repoPath: String) -> some View {
        let drag = interaction.dragging
        let isDragging = drag?.tab == repoPath
        return RepoTabChip(
            name: repoStore.repo(at: repoPath)?.name
                ?? (repoPath as NSString).lastPathComponent,
            isActive: workspace.activeTab == repoPath,
            isHovering: interaction.hoveredTab == repoPath,
            onClose: { name in
                workspace.requestCloseTab(repoPath, repoName: name)
            }
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: TabChipFramesKey.self,
                    value: [repoPath: geo.frame(in: .global)]
                )
            }
        )
        .offset(x: isDragging ? (drag?.translation ?? 0) : 0)
        .zIndex(isDragging ? 1 : 0)
        .opacity(isDragging ? 0.85 : 1)
        .animation(.easeInOut(duration: 0.15), value: workspace.openTabs)
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

/// Chip'lerin şerit koordinatındaki frame'leri (drop hedefi hesabı için).
private struct TabChipFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Repo tab'i (v1 globals.css .repo-tab): pasif şeffaf, aktif elevated +
/// accent kenarlık; kapatma butonu yalnız hover'da görünür, hover'ı kırmızı.
/// Seçme/sürükleme/hover chip'te DEĞİL — `TabStripInteractionView` (AppKit).
struct RepoTabChip: View {
    let name: String
    let isActive: Bool
    /// Hover, AppKit etkileşim katmanından gelir (`TabStripInteractionModel`).
    let isHovering: Bool
    let onClose: (String) -> Void

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
