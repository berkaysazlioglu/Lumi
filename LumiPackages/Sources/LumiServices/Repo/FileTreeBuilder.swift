import Foundation
import LumiKit

/// File tree üretimi (f4467ac davranışı):
/// ignored girdiler ÇIKARILMAZ, bayraklanır; istisna `.git` (her zaman gizli).
/// Ignored klasörlerin içine girilmez (node_modules performansı).
/// Sıralama: klasörler önce → ignored olmayanlar önce → localeCompare.
///
/// Tarama güvenliği (karar 28): her dizin kendi `autoreleasepool`unda taranır
/// (cooperative pool'da runloop drain'i yok — Foundation'ın autoreleased
/// NSString/NSURL çöpü aksi hâlde tarama boyunca birikir); symlink'ler
/// `lstat` ile tespit edilir ve TAKİP EDİLMEZ (döngü koruması + Electron dirent
/// paritesi); toplam girdi ve derinlik `Limits` ile tavanlanır.
enum FileTreeBuilder {
    /// Hardcoded default exclude listesi (Electron listesi + karar 28 eklemeleri) —
    /// git olmayan dizinler için tek filtre; git repolarında git semantiğinin
    /// üzerine eklenir. Unity (`Library`, `Temp`, `Logs`, `obj`) ve Xcode
    /// (`DerivedData`) çıktıları FSEvents gürültüsünün ana kaynağıdır.
    static let excludedNames: Set<String> = [
        ".git", "node_modules", "dist", "build", ".DS_Store",
        "coverage", ".next", ".nuxt", ".cache",
        "__pycache__", ".pytest_cache", "venv", ".venv",
        "Library", "Temp", "Logs", "obj", "DerivedData", ".build", "Pods",
    ]

    /// FSEvents filtresi için: `.git` hariç (git panel canlılığı .git içi
    /// değişimlere bağlı).
    static let watchNoiseNames: Set<String> = excludedNames.subtracting([".git"])

    struct Limits: Sendable {
        /// Ağaçtaki toplam düğüm tavanı; aşılınca alt dizinlere inilmez
        /// (o seviyenin girdileri yine listelenir, children boş kalır).
        let maxEntries: Int
        /// Kökten itibaren taranacak azami dizin derinliği.
        let maxDepth: Int

        static let `default` = Limits(maxEntries: 100_000, maxDepth: 32)
    }

    static func isHardcodedExcluded(_ name: String) -> Bool {
        if excludedNames.contains(name) { return true }
        if name.hasSuffix(".log") { return true }
        if name == ".env" || name.hasPrefix(".env.") { return true }
        return false
    }

    /// `ignoredPaths`: repo-köküne göre relative path'ler; tamamen-ignored
    /// dizinler trailing `/` ile gelir (`git ls-files -o -i --exclude-standard
    /// --directory -z` çıktısı).
    static func build(
        root: String,
        ignoredPaths: Set<String>,
        limits: Limits = .default
    ) -> [FileTreeNode] {
        var remainingEntries = limits.maxEntries
        return scan(
            directory: root,
            relativePrefix: "",
            depth: 1,
            ignoredPaths: ignoredPaths,
            limits: limits,
            remainingEntries: &remainingEntries
        )
    }

    private enum EntryKind {
        case file
        case directory
        case missing
    }

    /// `lstat`: symlink'i çözmez → symlink dizinler `.file` olarak görünür ve
    /// içine girilmez. Foundation'a göre autorelease çöpü de üretmez.
    private static func entryKind(at path: String) -> EntryKind {
        var info = stat()
        guard lstat(path, &info) == 0 else { return .missing }
        switch info.st_mode & S_IFMT {
        case S_IFDIR:
            return .directory
        case S_IFLNK:
            // Kırık symlink eskiden de (fileExists → false) elenirdi; parite korunur
            var target = stat()
            return stat(path, &target) == 0 ? .file : .missing
        default:
            return .file
        }
    }

    private static func scan(
        directory: String,
        relativePrefix: String,
        depth: Int,
        ignoredPaths: Set<String>,
        limits: Limits,
        remainingEntries: inout Int
    ) -> [FileTreeNode] {
        autoreleasepool {
            scanDirectory(
                directory: directory,
                relativePrefix: relativePrefix,
                depth: depth,
                ignoredPaths: ignoredPaths,
                limits: limits,
                remainingEntries: &remainingEntries
            )
        }
    }

    private static func scanDirectory(
        directory: String,
        relativePrefix: String,
        depth: Int,
        ignoredPaths: Set<String>,
        limits: Limits,
        remainingEntries: inout Int
    ) -> [FileTreeNode] {
        // Okunamayan dizin sessizce boş geçilir
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return []
        }
        remainingEntries -= entries.count

        var nodes: [FileTreeNode] = []
        nodes.reserveCapacity(entries.count)
        for name in entries where name != ".git" {
            let absolutePath = directory + "/" + name
            let kind = entryKind(at: absolutePath)
            guard kind != .missing else { continue }
            let relativePath = relativePrefix.isEmpty ? name : relativePrefix + "/" + name
            let isDirectory = kind == .directory
            let isIgnored = isHardcodedExcluded(name)
                || ignoredPaths.contains(relativePath)
                || (isDirectory && ignoredPaths.contains(relativePath + "/"))

            guard isDirectory else {
                nodes.append(FileTreeNode(name: name, path: relativePath, type: .file, isIgnored: isIgnored))
                continue
            }
            // Tavan her inişte yeniden değerlendirilir: kardeş dizinler bütçeyi tüketebilir
            let canDescend = remainingEntries > 0 && depth < limits.maxDepth
            let children = (isIgnored || !canDescend)
                ? []
                : scan(
                    directory: absolutePath,
                    relativePrefix: relativePath,
                    depth: depth + 1,
                    ignoredPaths: ignoredPaths,
                    limits: limits,
                    remainingEntries: &remainingEntries
                )
            nodes.append(FileTreeNode(
                name: name,
                path: relativePath,
                type: .folder,
                isIgnored: isIgnored,
                children: children
            ))
        }

        return nodes.sorted { lhs, rhs in
            if (lhs.type == .folder) != (rhs.type == .folder) {
                return lhs.type == .folder
            }
            if lhs.isIgnored != rhs.isIgnored {
                return !lhs.isIgnored
            }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }
}
