import LumiKit
import LumiState
import SwiftUI
import UniformTypeIdentifiers

/// Sol sidebar: Project Context file tree (spec/12 §9 UI davranışları).
/// Ignored öğeler soluk; ignored klasör expand edilemez; arama filtresi;
/// context menü (Copy Path / Reveal / Delete); terminale path sürükleme.
struct FileTreeSidebar: View {
    let repoPath: String
    let repoStore: RepoStore
    let onOpenFile: (String) -> Void
    let onReveal: (String) -> Void
    let onTrash: (String) -> Void

    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            sectionHeader
            searchField
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let nodes = filteredNodes
                    if nodes.isEmpty {
                        Text(searchText.isEmpty ? "(boş)" : "(eşleşme yok)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.textMuted)
                            .padding(10)
                    }
                    ForEach(nodes) { node in
                        nodeRows(node, level: 0)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Theme.bgSurface)
    }

    private var sectionHeader: some View {
        HStack {
            Text("FILES")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var searchField: some View {
        TextField("Search files…", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
    }

    private var filteredNodes: [FileTreeNode] {
        let tree = repoStore.fileTrees[repoPath] ?? []
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return tree }
        return Self.filter(tree, query: query.lowercased())
    }

    /// Arama kuralı (spec/12 §9): eşleşen dosyalar + altında eşleşme olan
    /// klasörler; klasör ADI eşleşirse tüm children korunur.
    static func filter(_ nodes: [FileTreeNode], query: String) -> [FileTreeNode] {
        nodes.compactMap { node in
            let nameMatches = node.name.lowercased().contains(query)
            if node.type == .file {
                return nameMatches ? node : nil
            }
            if nameMatches {
                return node
            }
            let filteredChildren = filter(node.children, query: query)
            guard !filteredChildren.isEmpty else { return nil }
            return FileTreeNode(
                name: node.name,
                path: node.path,
                type: .folder,
                isIgnored: node.isIgnored,
                children: filteredChildren
            )
        }
    }

    @ViewBuilder
    private func nodeRows(_ node: FileTreeNode, level: Int) -> AnyView {
        let isSearching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        let isExpanded = isSearching || repoStore.isNodeExpanded(repoPath, path: node.path)
        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                nodeRow(node, level: level, isExpanded: isExpanded)
                if node.type == .folder, isExpanded, !node.isIgnored {
                    ForEach(node.children) { child in
                        nodeRows(child, level: level + 1)
                    }
                }
            }
        )
    }

    private func nodeRow(_ node: FileTreeNode, level: Int, isExpanded: Bool) -> some View {
        Button {
            if node.type == .folder {
                guard !node.isIgnored else { return } // ignored klasör no-op (spec/12 §9)
                repoStore.toggleNode(repoPath, path: node.path)
            } else {
                onOpenFile(node.path)
            }
        } label: {
            HStack(spacing: 5) {
                if node.type == .folder {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: 10)
                } else {
                    Spacer().frame(width: 10)
                }
                Image(systemName: node.type == .folder ? "folder" : "doc")
                    .font(.system(size: 10))
                    .foregroundStyle(node.type == .folder ? Theme.accentPrimary : Theme.textMuted)
                Text(node.name)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(level) * 12 + 10)
            .padding(.trailing, 8)
            .padding(.vertical, 2.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(node.isIgnored ? 0.45 : 1) // ignored = soluk (spec/12 §9)
        .onDrag {
            // Terminale sürükleme: DropAwareTerminalView fileURL kabul eder
            NSItemProvider(object: URL(fileURLWithPath: repoPath + "/" + node.path) as NSURL)
        }
        .contextMenu {
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.path, forType: .string)
            }
            Button("Reveal in Finder") {
                onReveal(node.path)
            }
            if node.type == .file {
                Button("Delete", role: .destructive) {
                    onTrash(node.path)
                }
            }
        }
    }
}
