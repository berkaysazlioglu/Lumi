import LumiKit
import LumiState
import SwiftUI
import UniformTypeIdentifiers

struct ExplorerView: View {
    let repoPath: String
    @Shell private var shell
    @State private var contentSearch = false
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
            Picker("Explorer search mode", selection: $contentSearch) {
                Text("Names").tag(false)
                Text("Contents").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .font(Theme.Typography.ui(.label))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.sm)
            if contentSearch {
                ExplorerContentSearchView(repoPath: repoPath)
            } else {
                namesView
            }
        }
        .background(Theme.bgSurface)
        .onChange(of: tree) {
            let query = search.query
            search.cancel()
            search.setQuery(query, tree: tree)
        }
        .onChange(of: repoPath) { search.cancel(); selectedPath = nil }
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
            Button("New File…") { beginEdit(.newFile, parent: unityMode ? "Assets" : "") }
            Button("New Folder…") { beginEdit(.newFolder, parent: unityMode ? "Assets" : "") }
        }
    }

    private var namesView: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textMuted)
                TextField("Filter files…", text: Binding(
                    get: { search.query }, set: { search.setQuery($0, tree: tree) }
                ))
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
                .onKeyPress(.escape) { search.cancel(); return .handled }
                if !search.query.isEmpty {
                    IconButton(systemName: "xmark", label: "Clear filter", size: .caption) { search.cancel() }
                }
            }
            .font(Theme.Typography.ui(.body))
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Spacing.xxxl)
            .background(Theme.bgDeep)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if shell.repos.fileTrees[repoPath] == nil {
                            ProgressView().controlSize(.small).padding(Theme.Spacing.lg)
                        } else if rows.isEmpty {
                            EmptyStatePlaceholder(search.isSearching ? "No matching files" : "Empty directory", density: .inline)
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
            .disabled(contentSearch || search.isSearching || (shell.repos.expandedNodes[repoPath] ?? []).isEmpty)
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
            Menu {
                Button("New File…") { beginEdit(.newFile, parent: unityMode ? "Assets" : "") }
                Button("New Folder…") { beginEdit(.newFolder, parent: unityMode ? "Assets" : "") }
                Section("View Mode") {
                    Toggle("Unity Assets only", isOn: optionBinding(\.unityAssetsOnly))
                        .disabled(shell.repos.capabilities[repoPath]?.isUnityProject != true)
                }
                Toggle("Show Dotfiles", isOn: optionBinding(\.showDotfiles))
                Toggle("Show Ignored Files", isOn: optionBinding(\.showIgnoredFiles))
                Divider()
                Button("Reveal Project in Finder") { shell.reveal("") }
            } label: {
                Image(systemName: "ellipsis").font(Theme.Typography.ui(.body))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: Theme.Spacing.xxl, height: Theme.Spacing.xxl)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Explorer view options")
            .accessibilityLabel("Explorer view options")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Spacing.xxxl)
    }

    private func optionBinding(_ key: WritableKeyPath<ExplorerOptions, Bool>) -> Binding<Bool> {
        Binding(get: { options[keyPath: key] }, set: {
            var updated = options
            updated[keyPath: key] = $0
            shell.repos.setExplorerOptions(updated, for: repoPath)
        })
    }

    private func rowView(_ row: FileTreeRows.Row) -> some View {
        let status = shell.git.explorerStatuses[repoPath]?[row.path]
        let color = status.map(Theme.fileChangeColor) ?? (row.isIgnored ? Theme.textMuted : Theme.textPrimary)
        return HoverReader { hovering in
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: row.type == .folder ? (row.isExpanded ? "chevron.down" : "chevron.right") : "")
                    .font(Theme.Typography.ui(.caption))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: Theme.Spacing.lg)
                    .accessibilityHidden(true)
                Image(systemName: fileIcon(row))
                    .font(Theme.Typography.ui(.body))
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(row.name)
                    .font(Theme.Typography.ui(.body))
                    .italic(row.isIgnored)
                    .foregroundStyle(color)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let status {
                    Text(status.badgeText).foregroundStyle(color)
                        .font(Theme.Typography.ui(.caption, weight: .medium))
                } else if row.isIgnored {
                    Text("I").foregroundStyle(Theme.textMuted).font(Theme.Typography.ui(.caption))
                }
            }
            .padding(.leading, CGFloat(row.level) * Theme.Spacing.xl + Theme.Spacing.md)
            .padding(.trailing, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .background(selectedPath == row.path ? Theme.accentPrimary.opacity(0.15) : hovering ? Theme.bgElevated : .clear)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { selectedPath = row.path; if row.type == .file { shell.presentFile(row.path) } }
            .onTapGesture { selectedPath = row.path; if row.type == .folder { open(row) } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open(row) }
            .help(row.path)
            .onDrag { NSItemProvider(object: URL(fileURLWithPath: repoPath).appendingPathComponent(row.path) as NSURL) }
            .contextMenu {
                if row.type == .file {
                    Button("Open") { shell.presentFile(row.path) }
                    if status != nil { Button("Open Changes") { shell.presentDiff(row.path) } }
                }
                if row.type == .folder {
                    Button("New File…") { beginEdit(.newFile, parent: row.path) }
                    Button("New Folder…") { beginEdit(.newFolder, parent: row.path) }
                }
                Button("Rename…") {
                    editName = row.name
                    editPrompt = ExplorerEditPrompt(kind: .rename, repoPath: repoPath, path: row.path)
                }
                Button("Copy Path") { copy(URL(fileURLWithPath: repoPath).appendingPathComponent(row.path).path) }
                Button("Copy Relative Path") { copy(row.path) }
                Button("Reveal in Finder") { shell.reveal(row.path) }
                Divider()
                Button("Move to Trash", role: .destructive) { shell.trash(row.path) }
            }
        }
    }

    private func beginEdit(_ kind: ExplorerEditPrompt.Kind, parent: String) {
        editName = ""
        editPrompt = ExplorerEditPrompt(kind: kind, repoPath: repoPath, path: parent)
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

    private func fileIcon(_ row: FileTreeRows.Row) -> String {
        if row.type == .folder { return row.isExpanded ? "folder.fill" : "folder" }
        switch (row.name as NSString).pathExtension.lowercased() {
        case "swift", "cs", "ts", "tsx", "js", "json", "shader": return "curlybraces"
        case "png", "jpg", "jpeg", "gif", "svg", "tga": return "photo"
        case "unity", "prefab", "asset", "mat": return "cube"
        case "md", "txt": return "doc.text"
        default: return "doc"
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

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
