import LumiKit
import LumiState
import SwiftUI

/// Header tab şeridi: repo tab'leri + (+) butonu tek HStack'te. (+) her zaman
/// son tab'ın HEMEN ardında durur. Şerit kalan tüm genişliği alır; tab'lar
/// sığmazsa metinleri kısalarak daralır (ikon + kapatma her zaman görünür) —
/// eski sabit 600px + ScrollView kesmesi yok.
///
/// Sürükleyerek yeniden sıralama BİLİNÇLİ olarak yok (karar 27): pencerenin üst
/// 28px titlebar bölgesinde SwiftUI hosting içindeki her sürükleme pencereyi de
/// taşır; ölçülen hiçbir view/window düzeyi önlem bunu güvenilir biçimde
/// engellemedi.
struct RepoTabStrip: View {
    let workspace: WorkspaceStore
    let repoStore: RepoStore

    @State private var isAddRepoHovering = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(workspace.openTabs, id: \.self) { repoPath in
                RepoTabChip(
                    name: repoStore.repo(at: repoPath)?.name
                        ?? (repoPath as NSString).lastPathComponent,
                    isActive: workspace.activeTab == repoPath,
                    onSelect: { workspace.setActiveTab(repoPath) },
                    onClose: { name in
                        workspace.requestCloseTab(repoPath, repoName: name)
                    }
                )
            }
            addRepoButton
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var addRepoButton: some View {
        Button {
            workspace.isRepoSelectorOpen.toggle()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isAddRepoHovering ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: TopBarMetrics.controlHeight, height: TopBarMetrics.controlHeight)
                .background(isAddRepoHovering ? Theme.bgElevated : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
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
        HStack(spacing: 5) {
            Image(systemName: "folder")
                .font(.system(size: 10))
            Text(name)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 120, alignment: .leading)
            closeButton
                .opacity(isHovering || isActive ? 1 : 0)
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: TopBarMetrics.controlHeight)
        .background(isActive ? Theme.bgElevated : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(
                    isActive ? Theme.accentVivid.opacity(0.25) : Color.clear,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
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
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(isCloseHovering ? Theme.error : Theme.textMuted)
                .frame(width: 16, height: 16)
                .background(isCloseHovering ? Theme.error.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isCloseHovering = $0 }
    }
}
