import Foundation
import LumiKit

/// File tree üretimi (spec/12 §9, f4467ac davranışı):
/// ignored girdiler ÇIKARILMAZ, bayraklanır; istisna `.git` (her zaman gizli).
/// Ignored klasörlerin içine girilmez (node_modules performansı).
/// Sıralama: klasörler önce → ignored olmayanlar önce → localeCompare.
enum FileTreeBuilder {
    /// Hardcoded default exclude listesi (spec/12 §9) — git olmayan dizinler için
    /// tek filtre; git repolarında git semantiğinin üzerine eklenir.
    static let excludedNames: Set<String> = [
        ".git", "node_modules", "dist", "build", ".DS_Store",
        "coverage", ".next", ".nuxt", ".cache",
        "__pycache__", ".pytest_cache", "venv", ".venv",
    ]

    static func isHardcodedExcluded(_ name: String) -> Bool {
        if excludedNames.contains(name) { return true }
        if name.hasSuffix(".log") { return true }
        if name == ".env" || name.hasPrefix(".env.") { return true }
        return false
    }

    /// `ignoredPaths`: repo-köküne göre relative path'ler; tamamen-ignored
    /// dizinler trailing `/` ile gelir (`git ls-files -o -i --exclude-standard
    /// --directory -z` çıktısı).
    static func build(root: String, ignoredPaths: Set<String>) -> [FileTreeNode] {
        scan(directory: root, relativePrefix: "", ignoredPaths: ignoredPaths)
    }

    private static func scan(
        directory: String,
        relativePrefix: String,
        ignoredPaths: Set<String>
    ) -> [FileTreeNode] {
        // Okunamayan dizin sessizce boş geçilir (spec/12 §9)
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return []
        }

        var nodes: [FileTreeNode] = entries.compactMap { name in
            guard name != ".git" else { return nil }
            let absolutePath = directory + "/" + name
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: absolutePath, isDirectory: &isDirectory) else {
                return nil
            }
            let relativePath = relativePrefix.isEmpty ? name : relativePrefix + "/" + name
            let isIgnored = isHardcodedExcluded(name)
                || ignoredPaths.contains(relativePath)
                || (isDirectory.boolValue && ignoredPaths.contains(relativePath + "/"))

            if isDirectory.boolValue {
                let children = isIgnored
                    ? []
                    : scan(
                        directory: absolutePath,
                        relativePrefix: relativePath,
                        ignoredPaths: ignoredPaths
                    )
                return FileTreeNode(
                    name: name,
                    path: relativePath,
                    type: .folder,
                    isIgnored: isIgnored,
                    children: children
                )
            }
            return FileTreeNode(name: name, path: relativePath, type: .file, isIgnored: isIgnored)
        }

        nodes.sort { lhs, rhs in
            if (lhs.type == .folder) != (rhs.type == .folder) {
                return lhs.type == .folder
            }
            if lhs.isIgnored != rhs.isIgnored {
                return !lhs.isIgnored
            }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
        return nodes
    }
}
