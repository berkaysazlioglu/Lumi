import Foundation
import LumiKit

/// Path-traversal guard'ı (karar 11: TÜM path alan yollarda). `GitService` ve
/// `FileSystemOperations` (trash/reveal) ortak kullanır — tek doğrulama kuralı.
///
/// İki taraf da `resolvingSymlinksInPath()` ile canonicalize edilir: aksi halde
/// repo içindeki bir symlink repo DIŞINA işaret ettiğinde guard geçiliyordu
/// (ayrıca `/var` ↔ `/private/var` uyumsuzluğu çözülür).
public struct RepoPathGuard: Sendable {
    public init() {}

    /// `relativePath`i `repoPath` köküne göre çözer; kök dışına çıkıyorsa
    /// `LumiError.pathOutsideRepo` fırlatır. Dönüş canonical mutlak path'tir.
    public func resolve(repoPath: String, relativePath: String) throws -> String {
        let root = Self.canonical(repoPath)
        let resolved = Self.canonical(relativePath, relativeTo: root)
        guard Self.isContained(resolved, in: root) else {
            throw LumiError.pathOutsideRepo(path: relativePath)
        }
        return resolved
    }

    /// Mutlak bir path verilen köklerden en az birinin altında mı? Kökler
    /// canonical'a çevrilir; boş kök listesi hiçbir şeye izin vermez.
    public func isInside(anyOf roots: [String], path: String) -> Bool {
        let resolved = Self.canonical(path)
        return roots.contains { root in
            let canonicalRoot = Self.canonical(root)
            guard !canonicalRoot.isEmpty else { return false }
            return Self.isContained(resolved, in: canonicalRoot)
        }
    }

    // MARK: - Yardımcılar

    static func canonical(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    static func canonical(_ path: String, relativeTo root: String) -> String {
        URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: root))
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    static func isContained(_ path: String, in root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }
}
