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

    static let filterDebounce: Duration = .milliseconds(150)

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
        HStack(spacing: 4) {
            if isSearchOpen {
                SidebarSearchInput(
                    text: searchBinding,
                    placeholder: "Filter files...",
                    onClose: { closeSearch() }
                )
            } else {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet.indent")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.accentPrimary)
                        Text("PROJECT CONTEXT")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .tracking(0.6)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 4)
                FileTreeHeaderAction(icon: "magnifyingglass", size: 11) {
                    isSearchOpen = true
                }
                .help("Filter files")
            }
            FileTreeHeaderAction(icon: isExpanded ? "chevron.down" : "chevron.right", size: 11) {
                isExpanded.toggle()
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
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
                    Text(isSearching ? "No matching files" : "Empty directory")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                        .padding(10)
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
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: 10)
                } else {
                    Spacer().frame(width: 10)
                }
                Image(systemName: row.type == .folder ? "folder" : "doc")
                    .font(.system(size: 10))
                    .foregroundStyle(row.type == .folder ? Theme.warning : Theme.textMuted)
                Text(row.name)
                    .font(.system(size: 11.5, design: .monospaced))
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
                .font(.system(size: 10))
                .foregroundStyle(Theme.textMuted)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .focused($isFocused)
                .onKeyPress(.escape) {
                    onClose()
                    return .handled
                }
            if !text.isEmpty {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Theme.bgDeep)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused ? Theme.accentPrimary : Theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear { isFocused = true }
        .onChange(of: isFocused) { _, focused in
            // v1: input boşken blur → arama kapanır
            if !focused, text.trimmingCharacters(in: .whitespaces).isEmpty {
                onClose()
            }
        }
    }
}

/// v1 file-tree-header__action: küçük, sessiz ikon butonu (hover'da aydınlanır).
private struct FileTreeHeaderAction: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isHovering ? Theme.textPrimary : Theme.textMuted)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
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
