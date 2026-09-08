import LumiKit
import LumiState
import SwiftUI

/// Repo açma dropdown'u (v1 repo-dropdown paritesi).
/// Arama input'u (auto-focus, case-insensitive substring), açık tab'lar
/// gizlenir, çoklu grupta collapse/expand (session-local), ↑/↓/Enter klavye
/// navigasyonu (yalnız açık grupların düz listesi), git badge'i, boş durumlar.
struct RepoSelectorView: View {
    let groups: [RepoStore.RepoGroup]
    let excludedRepoPaths: Set<String>
    @Binding var collapsedGroups: Set<String>
    let onSelect: (Repo) -> Void

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    /// Dropdown'ın kendi geometrisi; ikisi de ölçek dışı ara değerler
    /// (v1 repo-dropdown paritesi).
    private enum Metrics {
        static let width: CGFloat = 320
        static let maxListHeight: CGFloat = 320
    }

    // MARK: - Body

    /// Filtre/düzleştirme mantığı `RepoStore`'da (refactor 7.5): view yalnız
    /// sonucu çizer.
    var body: some View {
        let visible = RepoStore.filteredGroups(
            groups,
            excluding: excludedRepoPaths,
            matching: searchText
        )
        let flat = RepoStore.flatRepos(visible, collapsed: collapsedGroups)
        VStack(spacing: 0) {
            searchRow(flat: flat)
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
            if visible.allSatisfy(\.repos.isEmpty) {
                emptyState
            } else {
                repoList(visible, flat: flat)
            }
        }
        .frame(width: Metrics.width)
        .background(Theme.bgSurface)
        .onChange(of: searchText) {
            selectedIndex = 0
        }
    }

    // MARK: - Arama satırı (v1 repo-dropdown__search)

    private func searchRow(flat: [Repo]) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.textMuted)
                .accessibilityHidden(true)
            TextField("Search repos...", text: $searchText)
                .textFieldStyle(.plain)
                .font(Theme.Typography.baseMono)
                .foregroundStyle(Theme.textPrimary)
                .focused($isSearchFocused)
                .onKeyPress(.downArrow) {
                    selectedIndex = min(selectedIndex + 1, max(flat.count - 1, 0))
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    selectedIndex = max(selectedIndex - 1, 0)
                    return .handled
                }
                .onKeyPress(.return) {
                    guard flat.indices.contains(selectedIndex) else { return .ignored }
                    onSelect(flat[selectedIndex])
                    return .handled
                }
        }
        .padding(Theme.Spacing.lg)
        .onAppear { isSearchFocused = true }
    }

    // MARK: - Liste

    private func repoList(_ visible: [RepoStore.RepoGroup], flat: [Repo]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    // Tek grup → düz liste; çoklu grup → collapsible başlıklar (v1)
                    if visible.count > 1 {
                        ForEach(visible) { group in
                            groupSection(group, flat: flat)
                        }
                    } else {
                        ForEach(visible.first?.repos ?? []) { repo in
                            repoRow(repo, flat: flat)
                        }
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .frame(maxHeight: Metrics.maxListHeight)
            .onChange(of: selectedIndex) {
                guard flat.indices.contains(selectedIndex) else { return }
                proxy.scrollTo(flat[selectedIndex].path)
            }
        }
    }

    /// Grup başlığı ortak `SectionHeader`'dır (Faz 7.2). Aç/kapa `onToggle`
    /// yerine dıştaki `Button`'a bağlıdır: satırın TAMAMI tıklanabilir kalsın
    /// (SectionHeader'ın kendi butonu yalnız etiketi kaplar).
    @ViewBuilder
    private func groupSection(_ group: RepoStore.RepoGroup, flat: [Repo]) -> some View {
        let isCollapsed = collapsedGroups.contains(group.id)
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Button {
                if isCollapsed {
                    collapsedGroups.remove(group.id)
                } else {
                    collapsedGroups.insert(group.id)
                }
            } label: {
                SectionHeader(
                    title: group.label,
                    count: .init(value: group.repos.count, shape: .capsule, size: .caption),
                    disclosure: .leading,
                    isExpanded: !isCollapsed
                )
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(group.label), \(isCollapsed ? "expand" : "collapse") group"
            )
            if !isCollapsed {
                if group.repos.isEmpty {
                    EmptyStatePlaceholder("No repositories found", density: .inline)
                } else {
                    ForEach(group.repos) { repo in
                        repoRow(repo, flat: flat)
                    }
                }
            }
        }
    }

    private func repoRow(_ repo: Repo, flat: [Repo]) -> some View {
        RepoSelectorRow(
            repo: repo,
            isSelected: flat.indices.contains(selectedIndex)
                && flat[selectedIndex].path == repo.path
        ) {
            onSelect(repo)
        }
        .id(repo.path)
    }

    private var emptyState: some View {
        Text(
            searchText.trimmingCharacters(in: .whitespaces).isEmpty
                ? "No more repos available"
                : "No matching repos"
        )
        // Ortalanmış tek satır: `EmptyStatePlaceholder` yatay hizası bu kapta
        // tutmuyor (inline/panel sola yaslı, full ise kabı doldurur).
        .font(Theme.Typography.bodyMono)
        .foregroundStyle(Theme.textMuted)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
    }
}

/// v1 repo-dropdown__item: ikon + ad + git badge'i; hover/klavye seçimi
/// elevated zemin. Hover state'i `HoverReader`'ın içindedir (Faz 7.2).
private struct RepoSelectorRow: View {
    let repo: Repo
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HoverReader { isHovering in
            Button(action: onSelect) {
                row(highlighted: isSelected || isHovering)
            }
            .buttonStyle(.plain)
        }
    }

    private func row(highlighted: Bool) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: repo.isGitRepo ? "folder.badge.gearshape" : "folder")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.accentPrimary)
                .accessibilityHidden(true)
            Text(repo.name)
                .font(Theme.Typography.baseMono)
                .foregroundStyle(highlighted ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if repo.isGitRepo {
                Badge(text: "git", size: .caption, weight: .regular, style: .neutral)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(highlighted ? Theme.bgElevated : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview("RepoSelectorView") {
    RepoSelectorView(
        groups: RepoStore.RepoGroup.previewGroups,
        excludedRepoPaths: ["/Users/preview/Projects/lumi"],
        collapsedGroups: .constant(["standalone"]),
        onSelect: { _ in }
    )
    .background(Theme.bgDeep)
}
#endif
