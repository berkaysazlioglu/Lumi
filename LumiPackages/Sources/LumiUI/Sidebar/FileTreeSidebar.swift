import LumiKit
import LumiState
import SwiftUI
import UniformTypeIdentifiers

/// Sol sidebar "Project Context" bölümü (v1 ProjectContext paritesi). Başlık tıklaması bölümü collapse eder; büyüteç, başlığın
/// yerine geçen arama input'unu açar (auto-focus, ESC veya boşken blur kapatır).
/// Ignored öğeler soluk; ignored klasör expand edilemez; context menü
/// (Copy Path / Reveal / Delete); terminale path sürükleme.
///
/// Donma önlemi: ağaç FileTreeRows ile DÜZ satır listesine indirgenir (tek
/// seviyeli LazyVStack gerçekten lazy çizer) ve arama filtresi debounce +
/// background task'te koşar — büyük repoda her tuş vuruşunda main thread'de
/// recursive tarama yapılmaz (v1'deki arama donmasının önlemi). Faz 6.7: bu
/// debounce/iptal makinesi `LumiState.FileTreeSearchModel`'e taşındı; burada
/// yalnız render + "arama açık mı" kabuğu kaldı.
/// Faz 6.2: parent closure'ları kalktı — dosya açma/reveal/trash doğrudan
/// `ShellContext` üzerinden akar. `repoPath`'i `FileTreePanelItem` verir
/// (`.onChange(of: repoPath)` aynı view kimliğinde çalışsın diye parametre
/// olarak kalır).
struct FileTreeSidebar: View {
    let repoPath: String

    @Shell private var shell

    static let filterDebounce = Theme.Motion.searchDebounce

    @State private var isExpanded = true
    @State private var isSearchOpen = false
    /// Debounce + iptal + sıra garantisi `LumiState`'te (refactor 6.7); view
    /// yalnız sorguyu iletir ve hazır sonucu çizer.
    @State private var search = FileTreeSearchModel<[FileTreeRows.Row]>(
        debounce: FileTreeSidebar.filterDebounce,
        search: { nodes, query in FileTreeRows.searchRows(nodes, query: query) }
    )

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                treeList
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 8)
        .background(Theme.bgSurface)
        .onChange(of: repoPath) {
            // Repo değişince arama sıfırlanır (v1 paritesi)
            closeSearch()
        }
        .onChange(of: shell.repos.fileTrees[repoPath]) {
            // Watcher ağacı tazelerse aktif arama sonucu da tazelenir
            search.setQuery(search.query, tree: tree)
        }
    }

    // MARK: - Header (v1 file-tree-header)

    private var header: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if isSearchOpen {
                SidebarSearchInput(
                    text: searchBinding,
                    placeholder: "Filter files...",
                    onClose: { closeSearch() }
                )
            } else {
                SectionHeader(
                    title: "Project Context",
                    icon: "list.bullet.indent",
                    onToggle: { isExpanded.toggle() }
                ) {
                    IconButton(
                        systemName: "magnifyingglass",
                        label: "Filter files",
                        weight: .semibold
                    ) {
                        isSearchOpen = true
                    }
                }
            }
            IconButton(
                systemName: isExpanded ? "chevron.down" : "chevron.right",
                label: isExpanded ? "Collapse project context" : "Expand project context",
                weight: .semibold
            ) {
                isExpanded.toggle()
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.md)
        .frame(minHeight: 28)
    }

    // MARK: - Ağaç

    /// Aktif repo'nun (stale-while-revalidate) ağacı.
    private var tree: [FileTreeNode] {
        shell.repos.fileTrees[repoPath] ?? []
    }

    private var rows: [FileTreeRows.Row] {
        if isSearching, let results = search.results {
            return results
        }
        return FileTreeRows.visibleRows(
            tree,
            expanded: shell.repos.expandedNodes[repoPath] ?? []
        )
    }

    private var isSearching: Bool { search.isSearching }

    private var searchBinding: Binding<String> {
        Binding(
            get: { search.query },
            set: { search.setQuery($0, tree: tree) }
        )
    }

    private var treeList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let visible = rows
                if visible.isEmpty {
                    EmptyStatePlaceholder(
                        isSearching ? "No matching files" : "Empty directory",
                        density: .inline
                    )
                }
                ForEach(visible) { row in
                    rowView(row)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func rowView(_ row: FileTreeRows.Row) -> some View {
        Button {
            if row.type == .folder {
                // Aramada görünüm zaten tam açık; toggle sürpriz state bırakır.
                guard !isSearching else { return }
                guard !row.isIgnored else { return } // ignored klasör no-op
                shell.repos.toggleNode(repoPath, path: row.path)
            } else {
                shell.presentFile(row.path)
            }
        } label: {
            HStack(spacing: 5) {
                if row.type == .folder {
                    Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                        .font(Theme.Typography.ui(.micro, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: 10)
                        .accessibilityHidden(true)
                } else {
                    Spacer().frame(width: 10)
                }
                Image(systemName: row.type == .folder ? "folder" : "doc")
                    .font(Theme.Typography.ui(.caption))
                    .foregroundStyle(row.type == .folder ? Theme.warning : Theme.textMuted)
                    .accessibilityHidden(true)
                Text(row.name)
                    .font(Theme.Typography.mono(.label))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(row.level) * 12 + 10)
            .padding(.trailing, 8)
            .padding(.vertical, 2.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(row.isIgnored ? 0.45 : 1) // ignored = soluk
        .onDrag {
            // Terminale sürükleme: DropAwareTerminalView fileURL kabul eder
            NSItemProvider(object: URL(fileURLWithPath: repoPath + "/" + row.path) as NSURL)
        }
        .contextMenu {
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.path, forType: .string)
            }
            Button("Reveal in Finder") {
                shell.reveal(row.path)
            }
            if row.type == .file {
                Button("Delete", role: .destructive) {
                    shell.trash(row.path)
                }
            }
        }
    }

    // MARK: - Arama

    private func closeSearch() {
        search.cancel()
        isSearchOpen = false
    }
}

/// v1 SearchInput paritesi: bgDeep zemin, 28px, focus'ta accent kenarlık,
/// değer varken X butonu; ESC veya boşken focus kaybı kapatır.
struct SidebarSearchInput: View {
    @Binding var text: String
    let placeholder: String
    let onClose: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.ui(.caption))
                .foregroundStyle(Theme.textMuted)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Typography.mono(.body))
                .foregroundStyle(Theme.textPrimary)
                .focused($isFocused)
                .onKeyPress(.escape) {
                    onClose()
                    return .handled
                }
            if !text.isEmpty {
                IconButton(
                    systemName: "xmark",
                    label: "Clear filter",
                    size: .tiny,
                    side: nil,
                    showsHoverBackground: false,
                    action: onClose
                )
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Theme.bgDeep)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(isFocused ? Theme.accentPrimary : Theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .onAppear { isFocused = true }
        .onChange(of: isFocused) { _, focused in
            // v1: input boşken blur → arama kapanır
            if !focused, text.trimmingCharacters(in: .whitespaces).isEmpty {
                onClose()
            }
        }
    }
}

/// `.fileTree` panel öğesi — aktif repo'yu çözer, gerisi `FileTreeSidebar`.
public struct FileTreePanelItem: View {
    @Shell private var shell

    public init() {}

    public var body: some View {
        if let repoPath = shell.activeRepoPath {
            FileTreeSidebar(repoPath: repoPath)
        }
    }
}

#if DEBUG
#Preview("FileTreeSidebar") {
    FileTreeSidebar(repoPath: "/Users/preview/Projects/lumi")
        .frame(width: 280, height: 420)
        .environment(\.shell, ShellContext.preview())
}
#endif
