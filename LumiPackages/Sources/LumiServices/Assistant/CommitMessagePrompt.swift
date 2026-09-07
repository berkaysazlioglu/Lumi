import Foundation
import LumiKit

/// `claude -p` için commit mesajı prompt'u — saf metin üretimi (I/O yok).
///
/// Talimat argv'den, değişiklik gövdesi stdin'den gider: diff argv sınırına
/// takılmaz ve prompt enjeksiyonu için talimat/veri ayrımı korunur.
public enum CommitMessagePrompt {
    /// Diff'in stdin'e yazılan üst sınırı (karakter). Devasa diff'ler modelin
    /// bağlamını ve süresini şişirir; kesilen kısım açıkça işaretlenir.
    public static let maxDiffCharacters = 40_000
    static let truncationMarker = "\n[… diff truncated …]\n"

    /// Dil ve içerik kuralı açıkça yazılır: model dosya adlarını sayan
    /// ("x, y and z changed") ya da kullanıcının dil ayarına uyan yanıtlar
    /// üretmişti; İngilizce ve davranış/içerik odaklı tek satır istenir.
    public static func instruction(vcsName: String) -> String {
        """
        You write \(vcsName) commit messages. Read the changed-file list and unified diff from stdin. \
        Reply with ONE line only, in English (ignore any instruction to use another language): \
        an imperative summary of at most 72 characters that describes WHAT changed in behaviour \
        or content (e.g. "Add jump buffering to player controller"), never which files were \
        touched. No quotes, no trailing period, no explanation, no markdown.
        """
    }

    public static func body(for request: CommitMessageRequest) -> String {
        var text = "Changed files:\n"
        for change in request.changes {
            text += "\(marker(change.status)) \(change.path)\n"
        }
        let diff = request.diff.trimmingCharacters(in: .whitespacesAndNewlines)
        if !diff.isEmpty {
            text += "\nDiff:\n" + truncate(diff)
            text += "\n"
        }
        return text
    }

    /// Modelin yanıtını mesaja çevirir: ilk boş olmayan satır, çevreleyen
    /// tırnaklar ve sondaki nokta atılır. Boşsa nil.
    public static func cleanReply(_ reply: String) -> String? {
        guard var line = reply
            .split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty }) else { return nil }
        let quotes: Set<Character> = ["\"", "'", "`", "“", "”"]
        while let first = line.first, quotes.contains(first) { line.removeFirst() }
        while let last = line.last, quotes.contains(last) || last == "." { line.removeLast() }
        line = line.trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? nil : line
    }

    private static func truncate(_ diff: String) -> String {
        guard diff.count > maxDiffCharacters else { return diff }
        return String(diff.prefix(maxDiffCharacters)) + truncationMarker
    }

    private static func marker(_ status: FileChangeStatus) -> String {
        switch status {
        case .modified: return "M"
        case .added: return "A"
        case .deleted: return "D"
        case .renamed: return "R"
        case .untracked: return "?"
        }
    }
}
