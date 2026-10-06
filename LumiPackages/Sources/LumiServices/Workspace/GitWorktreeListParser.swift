import Foundation

/// `git worktree list --porcelain` ayrıştırıcısı (karar 115).
///
/// İki biçim tek döngüde: `-z` ile her alan NUL ile biter ve girdiler arasında
/// boş bir alan (çift NUL) vardır; eski git'te (`-z` < 2.36) aynı yapı satır
/// sonu ve boş satırla gelir. Yol olduğu gibi döner — kanonikleştirme ve
/// diskte varlık servisin işidir.
enum GitWorktreeListParser {
    struct RawEntry: Equatable {
        var path: String
        var branch: String?
        var isBare = false
        var isLocked = false
        var isPrunable = false
    }

    static func parse(_ output: String, nulSeparated: Bool) -> [RawEntry] {
        let separator: Character = nulSeparated ? "\0" : "\n"
        var entries: [RawEntry] = []
        var current: RawEntry?
        for field in output.split(separator: separator, omittingEmptySubsequences: false) {
            if field.isEmpty {
                if let entry = current { entries.append(entry) }
                current = nil
                continue
            }
            let (key, value) = split(field)
            if key == "worktree" {
                if let entry = current { entries.append(entry) }
                current = RawEntry(path: value)
                continue
            }
            guard current != nil else { continue }
            switch key {
            case "branch": current?.branch = shortBranch(value)
            case "bare": current?.isBare = true
            case "locked": current?.isLocked = true
            case "prunable": current?.isPrunable = true
            default: break  // HEAD, detached, sparse: kullanılmaz
            }
        }
        if let entry = current { entries.append(entry) }
        return entries
    }

    private static func split(_ field: Substring) -> (String, String) {
        guard let space = field.firstIndex(of: " ") else { return (String(field), "") }
        return (String(field[..<space]), String(field[field.index(after: space)...]))
    }

    private static func shortBranch(_ ref: String) -> String? {
        let prefix = "refs/heads/"
        let name = ref.hasPrefix(prefix) ? String(ref.dropFirst(prefix.count)) : ref
        return name.isEmpty ? nil : name
    }
}
