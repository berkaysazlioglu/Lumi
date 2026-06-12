import LumiKit
import LumiState
import SwiftUI

/// Repo açma dropdown'u (v1 repo-dropdown paritesi; spec/22 §2.3).
/// Arama input'u (auto-focus, case-insensitive substring), açık tab'lar
/// gizlenir, çoklu grupta collapse/expand (session-local), ↑/↓/Enter klavye
/// navigasyonu (yalnız açık grupların düz listesi), git badge'i, boş durumlar.
struct RepoSelectorView: View {
    let groups: [RepoStore.RepoGroup]
    let openTabPaths: Set<String>
    @Binding var collapsedGroups: Set<String>
    let onSelect: (Repo) -> Void

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    // MARK: - Saf filtre mantığı (test edilebilir)

    /// Açık tab'ları gizler + isimde case-insensitive substring filtresi;
    /// grup yapısı korunur (boş grup düşmez — gruplu görünümde boş mesajı çıkar).
    static func filteredGroups(
        _ groups: [RepoStore.RepoGroup],
        openTabPaths: Set<String>,
        query: String
    ) -> [RepoStore.RepoGroup] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return groups.map { group in
            RepoStore.RepoGroup(
                id: group.id,
                label: group.label,
                repos: group.repos.filter { repo in
                    guard !openTabPaths.contains(repo.path) else { return false }
                    return q.isEmpty || repo.name.lowercased().contains(q)
                }
            )
        }
    }

    /// Klavye navigasyonunun gezdiği düz liste — collapsed gruplar atlanır.
    static func flatRepos(
        _ groups: [RepoStore.RepoGroup],
        collapsed: Set<String>
    ) -> [Repo] {
        groups.flatMap { collapsed.contains($0.id) ? [] : $0.repos }
    }

    // MARK: - Body

    var body: some View {
        let visible = Self.filteredGroups(
            groups,
            openTabPaths: openTabPaths,
            query: searchText
        )
        let flat = Self.flatRepos(visible, collapsed: collapsedGroups)
        VStack(spacing: 0) {
            searchRow(flat: flat)
            Rectangle().fill(Theme.border).frame(height: 1)
            if visible.allSatisfy(\.repos.isEmpty) {
                emptyState
            } else {
                repoList(visible, flat: flat)
            }
        }
        .frame(width: 320)
        .background(Theme.bgSurface)
        .onChange(of: searchText) {
            selectedIndex = 0
        }
    }

    // MARK: - Arama satırı (v1 repo-dropdown__search)

    private func searchRow(flat: [Repo]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
            TextField("Search repos...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
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
        .padding(12)
        .onAppear { isSearchFocused = true }
    }

    // MARK: - Liste

    private func repoList(_ visible: [RepoStore.RepoGroup], flat: [Repo]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
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
                .padding(8)
            }
            .frame(maxHeight: 320)
            .onChange(of: selectedIndex) {
                guard flat.indices.contains(selectedIndex) else { return }
                proxy.scrollTo(flat[selectedIndex].path)
            }
        }
    }

    @ViewBuilder
    private func groupSection(_ group: RepoStore.RepoGroup, flat: [Repo]) -> some View {
        let isCollapsed = collapsedGroups.contains(group.id)
        VStack(alignment: .leading, spacing: 2) {
            Button {
                if isCollapsed {
                    collapsedGroups.remove(group.id)
                } else {
                    collapsedGroups.insert(group.id)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                    Text(group.label.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Theme.textMuted)
                    Text("\(group.repos.count)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Theme.bgDeep)
                        .clipShape(Capsule())
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !isCollapsed {
                if group.repos.isEmpty {
                    Text("No repositories found")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
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
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(Theme.textMuted)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// v1 repo-dropdown__item: ikon + ad + git badge'i; hover/klavye seçimi
/// elevated zemin.
private struct RepoSelectorRow: View {
    let repo: Repo
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: repo.isGitRepo ? "folder.badge.gearshape" : "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.accentPrimary)
                Text(repo.name)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(highlighted ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if repo.isGitRepo {
                    Text("git")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(highlighted ? Theme.bgElevated : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var highlighted: Bool {
        isSelected || isHovering
    }
}
