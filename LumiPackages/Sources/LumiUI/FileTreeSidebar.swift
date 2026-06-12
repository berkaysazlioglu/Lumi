import LumiKit
import LumiState
import SwiftUI
import UniformTypeIdentifiers

/// Sol sidebar "Project Context" bölümü (v1 ProjectContext paritesi; spec/12 §9,
/// spec/22 §3.2). Başlık tıklaması bölümü collapse eder; büyüteç, başlığın
/// yerine geçen arama input'unu açar (auto-focus, ESC veya boşken blur kapatır).
/// Ignored öğeler soluk; ignored klasör expand edilemez; context menü
/// (Copy Path / Reveal / Delete); terminale path sürükleme.
///
/// Donma önlemi: ağaç FileTreeRows ile DÜZ satır listesine indirgenir (tek
/// seviyeli LazyVStack gerçekten lazy çizer) ve arama filtresi debounce +
/// background task'te koşar — büyük repoda her tuş vuruşunda main thread'de
/// recursive tarama yapılmaz (v1'deki arama donmasının önlemi).
struct FileTreeSidebar: View {
    let repoPath: String
    let repoStore: RepoStore
    let onOpenFile: (String) -> Void
    let onReveal: (String) -> Void
    let onTrash: (String) -> Void

    static let filterDebounce: Duration = .milliseconds(150)

    @State private var isExpanded = true
    @State private var isSearchOpen = false
    @State private var searchText = ""
    /// Background filtrenin son sonucu; nil = arama kapalı/sonuç beklenirken
    /// normal ağaç gösterilir (stale-while-filter).
    @State private var searchResult: [FileTreeRows.Row]?
    @State private var filterTask: Task<Void, Never>?

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
        .onChange(of: searchText) { _, query in
            scheduleFilter(query)
        }
        .onChange(of: repoPath) {
            // Repo değişince arama sıfırlanır (v1 paritesi, spec/22 §3.2)
            closeSearch()
        }
        .onChange(of: repoStore.fileTrees[repoPath]) {
            // Watcher ağacı tazelerse aktif arama sonucu da tazelenir
            scheduleFilter(searchText)
        }
    }

    // MARK: - Header (v1 file-tree-header)

    private var header: some View {
        HStack(spacing: 4) {
            if isSearchOpen {
                SidebarSearchInput(
                    text: $searchText,
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

    private var rows: [FileTreeRows.Row] {
        if isSearching, let searchResult {
            return searchResult
        }
        return FileTreeRows.visibleRows(
            repoStore.fileTrees[repoPath] ?? [],
            expanded: repoStore.expandedNodes[repoPath] ?? []
        )
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
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
                guard !row.isIgnored else { return } // ignored klasör no-op (spec/12 §9)
                repoStore.toggleNode(repoPath, path: row.path)
            } else {
                onOpenFile(row.path)
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
        .opacity(row.isIgnored ? 0.45 : 1) // ignored = soluk (spec/12 §9)
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
                onReveal(row.path)
            }
            if row.type == .file {
                Button("Delete", role: .destructive) {
                    onTrash(row.path)
                }
            }
        }
    }

    // MARK: - Arama orkestrasyonu

    /// Debounce + background filtre: tuş vuruşu main thread'de tarama başlatmaz;
    /// debounce penceresinde yeni vuruş eskisini iptal eder, hesap nonisolated
    /// (global executor) koşar, yalnız sonuç MainActor'a döner.
    private func scheduleFilter(_ query: String) {
        filterTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResult = nil
            return
        }
        let tree = repoStore.fileTrees[repoPath] ?? []
        filterTask = Task {
            try? await Task.sleep(for: Self.filterDebounce)
            guard !Task.isCancelled else { return }
            let result = await Self.computeSearchRows(tree: tree, query: trimmed)
            guard !Task.isCancelled else { return }
            searchResult = result
        }
    }

    private nonisolated static func computeSearchRows(
        tree: [FileTreeNode],
        query: String
    ) async -> [FileTreeRows.Row] {
        FileTreeRows.searchRows(tree, query: query)
    }

    private func closeSearch() {
        filterTask?.cancel()
        filterTask = nil
        searchText = ""
        searchResult = nil
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
