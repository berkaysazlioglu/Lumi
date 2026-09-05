import LumiKit
import LumiState
import SwiftUI
import UniformTypeIdentifiers

struct ExplorerView: View {
    let repoPath: String
    @Shell private var shell
    @State private var mode: ExplorerSearchMode = .names
    /// Arama şeridinin TEK sorgusu — kip değişse de korunur; ad filtresi
    /// (`search`) ile içerik araması aynı metni okur.
    @State private var query = ""
    /// Contents kipinin eşleme seçenekleri ve dosya filtreleri (metin `query`).
    @State private var contentQuery = ExplorerContentQuery(text: "")
    @State private var showsOptions = false
    @State private var selectedPath: String?
    @State private var refreshing = false
    @State private var editPrompt: ExplorerEditPrompt?
    @State private var editName = ""
    @State private var search = FileTreeSearchModel<[FileTreeRows.Row]>(
        debounce: Theme.Motion.searchDebounce,
        search: { FileTreeRows.searchRows($0, query: $1) }
    )

    private var tree: [FileTreeNode] { shell.repos.explorerTrees[repoPath] ?? [] }
    private var options: ExplorerOptions { shell.repos.explorerOptions[repoPath] ?? ExplorerOptions() }
    private var unityMode: Bool {
        options.unityAssetsOnly && shell.repos.capabilities[repoPath]?.isUnityProject == true
    }
    private var rows: [FileTreeRows.Row] {
        if search.isSearching, let results = search.results { return results }
        return FileTreeRows.visibleRows(tree, expanded: shell.repos.expandedNodes[repoPath] ?? [])
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ExplorerQueryStrip(query: $query, mode: $mode, contentQuery: $contentQuery)
            if mode == .contents {
                ExplorerContentSearchView(repoPath: repoPath, query: contentQuery.with(text: query))
            } else {
                namesView
            }
        }
        .background(Theme.bgSurface)
        .onChange(of: query) { syncNameFilter() }
        .onChange(of: mode) { syncNameFilter() }
        .onChange(of: tree) { syncNameFilter() }
        .onChange(of: repoPath) {
            query = ""
            search.cancel()
            selectedPath = nil
        }
        .onDisappear { search.cancel() }
        .alert(editPrompt?.title ?? "", isPresented: Binding(
            get: { editPrompt != nil }, set: { if !$0 { editPrompt = nil } }
        )) {
            TextField("Name", text: $editName)
            Button("Cancel", role: .cancel) { editPrompt = nil }
            Button("Save") { submitEdit() }
                .disabled(editName.isEmpty || editName.contains("/") || editName == "." || editName == "..")
        }
        .contextMenu {
            Button("New File…") { beginEdit(.newFile, path: unityMode ? "Assets" : "") }
            Button("New Folder…") { beginEdit(.newFolder, path: unityMode ? "Assets" : "") }
        }
    }

    /// Ad filtresi yalnız Names kipinde koşar; Contents kipine geçince
    /// uçuştaki filtre iptal edilir ama sorgu metni yerinde kalır.
    private func syncNameFilter() {
        if mode == .names {
            search.setQuery(query, tree: tree)
        } else {
            search.cancel()
        }
    }

    private var namesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if shell.repos.fileTrees[repoPath] == nil {
                        ProgressView().controlSize(.small).padding(Theme.Spacing.lg)
                    } else if rows.isEmpty {
                        EmptyStatePlaceholder(
                            search.isSearching ? "No matching files" : "Empty directory",
                            density: .inline
                        )
                    }
                    ForEach(rows) { row in rowView(row) }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { moveSelection(1, proxy: proxy); return .handled }
            .onKeyPress(.upArrow) { moveSelection(-1, proxy: proxy); return .handled }
            .onKeyPress(.return) {
                if let row = rows.first(where: { $0.path == selectedPath }) { open(row) }
                return .handled
            }
            .onKeyPress(.rightArrow) { expandSelection(true); return .handled }
            .onKeyPress(.leftArrow) { expandSelection(false); return .handled }
        }
    }

    private var toolbar: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text((repoPath as NSString).lastPathComponent + (unityMode ? " / Assets" : ""))
                .font(Theme.Typography.ui(.body, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            IconButton(systemName: "rectangle.compress.vertical", label: "Collapse all folders") {
                shell.repos.collapseAll(repoPath)
            }
            .disabled(mode == .contents || search.isSearching || (shell.repos.expandedNodes[repoPath] ?? []).isEmpty)
            IconButton(systemName: "arrow.clockwise", label: "Refresh Explorer") {
                let path = repoPath
                refreshing = true
                Task {
                    await shell.repos.loadFileTree(path)
                    if shell.repos.capabilities[path]?.isGitRepo == true { await shell.git.refresh(path) }
                    refreshing = false
                }
            }
            .disabled(refreshing)
            IconButton(systemName: "ellipsis", label: "Explorer view options", size: .body) {
                showsOptions.toggle()
            }
            .popover(isPresented: $showsOptions, arrowEdge: .bottom) {
                PopoverMenu(items: optionItems, dismiss: { showsOptions = false })
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Spacing.xxxl)
    }

    /// Görünüm seçenekleri menüsü (custom popover; native `Menu` panelin
    /// temasına uymuyordu).
    private var optionItems: [PopoverMenu.Item] {
        let isUnity = shell.repos.capabilities[repoPath]?.isUnityProject == true
        return [
            .action("New File…", icon: "doc.badge.plus") { beginEdit(.newFile, path: unityMode ? "Assets" : "") },
            .action("New Folder…", icon: "folder.badge.plus") { beginEdit(.newFolder, path: unityMode ? "Assets" : "") },
            .section("View Mode"),
            .toggle("Unity Assets only", isOn: options.unityAssetsOnly, isEnabled: isUnity) { toggleOption(\.unityAssetsOnly) },
            .toggle("Show Dotfiles", isOn: options.showDotfiles) { toggleOption(\.showDotfiles) },
            .toggle("Show Ignored Files", isOn: options.showIgnoredFiles) { toggleOption(\.showIgnoredFiles) },
            .divider,
            .action("Reveal Project in Finder", icon: "folder") { shell.reveal("") },
        ]
    }

    private func toggleOption(_ key: WritableKeyPath<ExplorerOptions, Bool>) {
        var updated = options
        updated[keyPath: key].toggle()
        shell.repos.setExplorerOptions(updated, for: repoPath)
    }

    private func rowView(_ row: FileTreeRows.Row) -> some View {
        ExplorerRowView(
            repoPath: repoPath,
            row: row,
            isSelected: selectedPath == row.path,
            status: shell.git.explorerStatuses[repoPath]?[row.path],
            onSelect: { selectedPath = row.path },
            onOpen: { open(row) },
            onPresent: { shell.presentFile(row.path) },
            onEdit: { kind, path, name in beginEdit(kind, path: path, name: name) }
        )
    }

    private func beginEdit(_ kind: ExplorerEditPrompt.Kind, path: String, name: String = "") {
        editName = name
        editPrompt = ExplorerEditPrompt(kind: kind, repoPath: repoPath, path: path)
    }

    private func submitEdit() {
        guard let prompt = editPrompt, let edit = prompt.edit(name: editName) else { return }
        editPrompt = nil
        Task {
            await shell.toasts.reporting {
                try await shell.repos.editFile(edit, in: prompt.repoPath)
            }
        }
    }

    private func open(_ row: FileTreeRows.Row) {
        if row.type == .folder {
            if !search.isSearching && !row.isIgnored { shell.repos.toggleNode(repoPath, path: row.path) }
        } else { shell.presentFile(row.path) }
    }

    private func expandSelection(_ expand: Bool) {
        guard let row = rows.first(where: { $0.path == selectedPath }), row.type == .folder,
              row.isExpanded != expand else { return }
        open(row)
    }

    private func moveSelection(_ delta: Int, proxy: ScrollViewProxy) {
        let visible = rows
        guard !visible.isEmpty else { return }
        let current = visible.firstIndex { $0.path == selectedPath } ?? (delta > 0 ? -1 : visible.count)
        let next = min(max(current + delta, 0), visible.count - 1)
        selectedPath = visible[next].path
        proxy.scrollTo(visible[next].id)
    }
}
