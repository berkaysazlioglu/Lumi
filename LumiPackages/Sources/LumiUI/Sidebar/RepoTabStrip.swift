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
    @Shell private var shell

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(shell.navigation.openTabs, id: \.self) { repoPath in
                RepoTabChip(
                    name: shell.repos.repo(at: repoPath)?.name
                        ?? (repoPath as NSString).lastPathComponent,
                    isActive: shell.navigation.activeRepoPath == repoPath,
                    onSelect: { shell.navigation.setRoute(.repo(repoPath)) },
                    onClose: { name in
                        shell.requestCloseTab(repoPath, repoName: name)
                    }
                )
            }
            addRepoButton
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var addRepoButton: some View {
        IconButton(
            systemName: "plus",
            label: "Open repository",
            size: .body,
            weight: .medium,
            side: TopBarMetrics.controlHeight,
            role: .toggle
        ) {
            shell.dialogs.isRepoSelectorOpen.toggle()
        }
        .popover(isPresented: Binding(
            get: { shell.dialogs.isRepoSelectorOpen },
            set: { shell.dialogs.isRepoSelectorOpen = $0 }
        )) {
            RepoSelectorView(
                groups: shell.repos.groupedRepos,
                excludedRepoPaths: Set(shell.navigation.openTabs),
                collapsedGroups: Binding(
                    get: { shell.dialogs.collapsedRepoGroups },
                    set: { shell.dialogs.collapsedRepoGroups = $0 }
                )
            ) { repo in
                shell.dialogs.isRepoSelectorOpen = false
                shell.navigation.openTab(repo.path)
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

    var body: some View {
        HoverReader { isHovering in
            // 5pt: ölçek dışı ara değer (v1 paritesi korunuyor).
            HStack(spacing: 5) {
                Button(action: onSelect) {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                            .font(Theme.Typography.ui(.caption))
                            .accessibilityHidden(true)
                        Text(name)
                            .font(Theme.Typography.mono(.body))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 120, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityAddTraits(isActive ? [.isSelected] : [])
                IconButton(
                    systemName: "xmark",
                    label: "Close \(name) tab",
                    size: .micro,
                    side: Theme.Spacing.xl,
                    role: .destructive
                ) {
                    onClose(name)
                }
                .opacity(isHovering || isActive ? 1 : 0)
            }
            // 10pt: ölçek dışı ara değer (v1 paritesi korunuyor).
            .padding(.leading, 10)
            .padding(.trailing, Theme.Spacing.xs)
            .frame(height: TopBarMetrics.controlHeight)
            .background(isActive ? Theme.bgElevated : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(
                        isActive ? Theme.accentVivid.opacity(0.25) : Color.clear,
                        lineWidth: Theme.Stroke.hairline
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .foregroundStyle(isActive ? Theme.accentPrimary : Theme.textSecondary)
        }
    }
}

#if DEBUG
#Preview("RepoTabStrip") {
    RepoTabStrip()
        .padding(Theme.Spacing.md)
        .background(Theme.bgSurface)
        .environment(\.shell, ShellContext.preview())
}
#endif
