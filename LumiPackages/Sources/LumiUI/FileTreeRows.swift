import LumiKit

/// File tree'nin görünür satırlarını üreten saf mantık (render'dan ayrık).
///
/// Ağaç düz satır listesine indirgenir; FileTreeSidebar tek seviyeli
/// `LazyVStack + ForEach` ile çizer. Recursive nested-VStack render'ı
/// LazyVStack'in lazy'liğini öldürüyordu — büyük repoda (özellikle aramada,
/// her şey expand'ken) binlerce satır eager kurulup UI'ı donduruyordu (v1'deki
/// arama donmasının SwiftUI karşılığı). Arama filtresi bu sayede background
/// task'te de koşabilir: girdi/çıktı Sendable değerler.
enum FileTreeRows {
    struct Row: Equatable, Identifiable, Sendable {
        let name: String
        /// Repo köküne göre relative path — satır kimliği.
        let path: String
        let type: FileTreeNode.NodeType
        let isIgnored: Bool
        /// Girinti seviyesi (kök = 0).
        let level: Int
        /// Klasörler için chevron yönü; dosyalarda her zaman false.
        let isExpanded: Bool

        var id: String { path }
    }

    /// Normal mod: expand durumuna göre görünür satırlar. Ignored klasör
    /// expand edilemez (spec/12 §9) — set'te olsa bile children gizli kalır.
    nonisolated static func visibleRows(
        _ nodes: [FileTreeNode],
        expanded: Set<String>
    ) -> [Row] {
        flatten(nodes, level: 0) { node in
            expanded.contains(node.path)
        }
    }

    /// Arama modu (spec/12 §9): eşleşen dosyalar + altında eşleşme olan
    /// klasörler; klasör ADI eşleşirse tüm children korunur. Sonuçta tüm
    /// klasörler açık gösterilir. `query` lowercase beklenmez — burada indirgenir.
    nonisolated static func searchRows(_ nodes: [FileTreeNode], query: String) -> [Row] {
        let filtered = filter(nodes, query: query.lowercased())
        return flatten(filtered, level: 0) { _ in true }
    }

    // MARK: - Yardımcılar

    private nonisolated static func flatten(
        _ nodes: [FileTreeNode],
        level: Int,
        isExpanded: (FileTreeNode) -> Bool
    ) -> [Row] {
        nodes.flatMap { node -> [Row] in
            let expandable = node.type == .folder && !node.isIgnored
            let expanded = expandable && isExpanded(node)
            let row = Row(
                name: node.name,
                path: node.path,
                type: node.type,
                isIgnored: node.isIgnored,
                level: level,
                isExpanded: expanded
            )
            guard expanded else { return [row] }
            return [row] + flatten(node.children, level: level + 1, isExpanded: isExpanded)
        }
    }

    private nonisolated static func filter(
        _ nodes: [FileTreeNode],
        query: String
    ) -> [FileTreeNode] {
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
}
