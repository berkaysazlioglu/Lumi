import Foundation

/// Yol karşılaştırmasının tek kapısı (karar 115): `~` açılır, `.`/`..`
/// sadeleşir, sembolik bağlar çözülür. macOS'ta `resolvingSymlinksInPath`
/// `/private/tmp` → `/tmp` indirger; iki taraf da buradan geçtiği sürece
/// eşitlik tutarlıdır.
///
/// Diskte olmayan yolda Foundation hiçbir bağı çözmez (`/private/tmp/x`
/// olduğu gibi kalır, var olan `/private/tmp` ise `/tmp` olur). Silinmiş bir
/// worktree'nin yolu kaydıyla eşleşebilsin diye en derin VAR OLAN ata çözülür
/// ve kalan bileşenler ona eklenir.
public enum CanonicalPath {
    public static func of(_ path: String) -> String {
        var existing = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        var missing: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            missing.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        return missing.reduce(existing.resolvingSymlinksInPath()) { $0.appendingPathComponent($1) }.path
    }

    /// `path`, `root`'un kendisi ya da altında mı (ikisi de kanonik olmalı).
    public static func contains(_ path: String, in root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}
