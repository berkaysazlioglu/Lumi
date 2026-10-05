import LumiKit
import LumiState
import SwiftUI

/// Favori dosya modalı (karar 107) — top bar `Files` listesindeki
/// `Add Files…` / `Manage Favorites…`.
///
/// Arama aktif checkout'un dosya ağacında yapılır; dosya adı ve klasör yolu
/// birlikte aranır (`FavoriteFileSearch`). Sonuca tıklamak (ya da ↩) favoriyi
/// ekler/çıkarır ve modal açık kalır — birden çok dosya art arda eklenir.
/// Arama boşken mevcut favoriler listelenir (çıkarma + kayıpları yeniden
/// bağlama). `relinkID` doluysa modal kayıp bir favoriyi yeni yerine bağlar:
/// seçilen sonuç onun yolunu alır ve modal kapanır.
public struct FavoriteFilesOverlay: View {
    @Shell private var shell
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var search = FileTreeSearchModel<[FavoriteFileCandidate]>(
        debounce: .milliseconds(80),
        search: { tree, query in FavoriteFileSearch.search(tree, query: query) }
    )
    @FocusState private var isSearchFocused: Bool

    public init() {}

    private static var panelWidth: CGFloat { Theme.scaled(640) }
    private static var panelHeight: CGFloat { Theme.scaled(560) }

    private var state: FavoriteFilesDialogState? {
        guard case .favoriteFiles(let state) = shell.dialogs.active else { return nil }
        return state
    }

    private var tree: [FileTreeNode]? {
        state.flatMap { shell.repos.fileTrees[$0.checkoutPath] }
    }

    private var results: [FavoriteFileCandidate] { search.results ?? [] }

    public var body: some View {
        ModalOverlay(onDismiss: dismiss) {
            Panel(variant: .modal) {
                VStack(spacing: 0) {
                    header
                    divider
                    searchRow
                    divider
                    if let state {
                        content(state)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
            }
            .frame(width: Self.panelWidth, height: Self.panelHeight)
        }
        .onAppear {
            query = state?.initialQuery ?? ""
            runSearch()
            isSearchFocused = true
        }
        .onChange(of: query) {
            selectedIndex = 0
            runSearch()
        }
        .onChange(of: state.flatMap { shell.repos.fileTreeRevisions[$0.checkoutPath] }) { runSearch() }
    }

    private func runSearch() {
        search.setQuery(query, tree: tree ?? [])
    }

    // MARK: - Başlık + arama

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(relinkTarget == nil ? "Favorite Files" : "Relink Favorite")
                    .font(Theme.Typography.mono(.headline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            IconButton(
                systemName: "xmark", label: "Close favorite files",
                side: Theme.scaled(28), cornerRadius: Theme.Radius.md, action: dismiss
            )
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.xl)
    }

    private var subtitle: String {
        if let relinkTarget {
            return "\(relinkTarget.relativePath) was moved or deleted — pick its new location"
        }
        let checkout = state.map { shell.checkoutLabel(for: $0.checkoutPath) } ?? "this project"
        return "Search \(checkout) by file or folder name — click a result to add it"
    }

    private var relinkTarget: ProjectFavoriteFile? {
        guard let id = state?.relinkID else { return nil }
        return shell.favoriteFiles.favorites.first { $0.id == id }
    }

    private var searchRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.textMuted)
                .accessibilityHidden(true)
            TextField("Search files and folders…", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.Typography.baseMono)
                .foregroundStyle(Theme.textPrimary)
                .focused($isSearchFocused)
                .onKeyPress(.downArrow) {
                    selectedIndex = min(selectedIndex + 1, max(results.count - 1, 0))
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    selectedIndex = max(selectedIndex - 1, 0)
                    return .handled
                }
                .onKeyPress(.return) {
                    guard search.isSearching, results.indices.contains(selectedIndex) else { return .ignored }
                    choose(results[selectedIndex])
                    return .handled
                }
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
    }

    // MARK: - İçerik

    @ViewBuilder
    private func content(_ state: FavoriteFilesDialogState) -> some View {
        if search.isSearching {
            if tree == nil {
                message("Indexing files…")
            } else if search.results == nil {
                message("Searching…")
            } else if results.isEmpty {
                message("No matching files")
            } else {
                resultList(state)
            }
        } else {
            favoriteList(state)
        }
    }

    private func resultList(_ state: FavoriteFilesDialogState) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, candidate in
                        resultRow(candidate, index: index, state: state).id(candidate.id)
                    }
                    if results.count >= FavoriteFileSearch.resultLimit {
                        Text("Showing the first \(FavoriteFileSearch.resultLimit) matches — refine the search")
                            .font(Theme.Typography.labelMono)
                            .foregroundStyle(Theme.textMuted)
                            .padding(Theme.Spacing.md)
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .onChange(of: selectedIndex) {
                guard results.indices.contains(selectedIndex) else { return }
                proxy.scrollTo(results[selectedIndex].id)
            }
        }
    }

    private func resultRow(_ candidate: FavoriteFileCandidate, index: Int, state: FavoriteFilesDialogState) -> some View {
        let isFavorite = shell.favoriteFiles.isFavorite(candidate.path, in: state.projectPath)
        return FavoriteFileRow(
            path: candidate.path,
            isMissing: false,
            isSelected: index == selectedIndex,
            action: { choose(candidate) }
        ) {
            if relinkTarget != nil {
                IconButton(systemName: "link", label: "Relink to this file", side: Theme.scaled(24)) {
                    choose(candidate)
                }
            } else {
                IconButton(
                    systemName: isFavorite ? "star.fill" : "star",
                    label: isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    side: Theme.scaled(24), role: .toggle, isActive: isFavorite
                ) { choose(candidate) }
            }
        }
    }

    @ViewBuilder
    private func favoriteList(_ state: FavoriteFilesDialogState) -> some View {
        let entries = shell.favoriteFiles.entries(
            projectPath: state.projectPath, checkoutPath: state.checkoutPath, tree: tree
        )
        if entries.isEmpty {
            message("No favorite files yet — type to search by file or folder name")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                    SectionHeader(title: "Favorites", count: .init(value: entries.count, shape: .capsule, size: .caption))
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.bottom, Theme.Spacing.xs)
                    ForEach(entries) { favoriteRow($0, state: state) }
                }
                .padding(Theme.Spacing.lg)
            }
        }
    }

    private func favoriteRow(_ entry: FavoriteFileEntry, state: FavoriteFilesDialogState) -> some View {
        FavoriteFileRow(
            path: entry.resolvedPath ?? entry.favorite.relativePath,
            detail: entry.isMissing ? "Not found — moved or deleted" : nil,
            isMissing: entry.isMissing,
            action: nil
        ) {
            if entry.isMissing {
                IconButton(systemName: "magnifyingglass", label: "Relink…", side: Theme.scaled(24)) {
                    shell.dialogs.present(.favoriteFiles(FavoriteFilesDialogState(
                        projectPath: state.projectPath, checkoutPath: state.checkoutPath,
                        relinkID: entry.favorite.id, initialQuery: entry.favorite.name
                    )))
                    query = entry.favorite.name
                }
            }
            IconButton(systemName: "trash", label: "Remove from Favorites", side: Theme.scaled(24), role: .destructive) {
                Task { await shell.favoriteFiles.remove(id: entry.favorite.id) }
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.bodyMono)
            .foregroundStyle(Theme.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xxxl)
    }

    // MARK: - Eylemler

    private func choose(_ candidate: FavoriteFileCandidate) {
        guard let state else { return }
        if let id = state.relinkID {
            Task {
                if await shell.favoriteFiles.relink(id: id, to: candidate.path) { dismiss() }
            }
        } else {
            Task { await shell.favoriteFiles.toggle(candidate.path, in: state.projectPath) }
        }
    }

    private func dismiss() {
        search.cancel()
        guard let state else { return }
        shell.dialogs.dismiss(.favoriteFiles(state))
    }
}
