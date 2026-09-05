import Foundation
import LumiKit

public struct ExplorerOptions: Equatable, Sendable {
    public var unityAssetsOnly = false
    public var showDotfiles = true
    public var showIgnoredFiles = false

    public init() {}

    public func project(_ nodes: [FileTreeNode], isUnityProject: Bool) -> [FileTreeNode] {
        let assetsOnly = unityAssetsOnly && isUnityProject
        let roots = assetsOnly
            ? nodes.first(where: { $0.path == "Assets" && $0.type == .folder })?.children ?? []
            : nodes
        return filter(roots, assetsOnly: assetsOnly)
    }

    private func filter(_ nodes: [FileTreeNode], assetsOnly: Bool) -> [FileTreeNode] {
        nodes.compactMap { node in
            guard showDotfiles || !node.name.hasPrefix("."),
                  showIgnoredFiles || !node.isIgnored,
                  !assetsOnly || !node.name.lowercased().hasSuffix(".meta") else { return nil }
            return FileTreeNode(
                name: node.name, path: node.path, type: node.type, isIgnored: node.isIgnored,
                children: filter(node.children, assetsOnly: assetsOnly)
            )
        }
    }
}

public enum ExplorerGitDecoration {
    /// Build once per status refresh; folder colors exclude deleted descendants.
    public static func statuses(_ changes: [GitFileChange]) -> [String: FileChangeStatus] {
        var result: [String: FileChangeStatus] = [:]
        for change in changes {
            let path = change.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            result[path] = dominant(result[path], change.status)
            guard change.status != .deleted else { continue }
            var parts = path.split(separator: "/").map(String.init)
            while parts.count > 1 {
                parts.removeLast()
                let parent = parts.joined(separator: "/")
                result[parent] = dominant(result[parent], change.status)
            }
        }
        return result
    }

    private static func dominant(_ existing: FileChangeStatus?, _ incoming: FileChangeStatus) -> FileChangeStatus {
        guard let existing else { return incoming }
        let priority: [FileChangeStatus] = [.modified, .deleted, .renamed, .added, .untracked]
        return priority.firstIndex(of: existing)! <= priority.firstIndex(of: incoming)! ? existing : incoming
    }
}
