import Foundation
import LumiKit

/// Araç çıktılarının biçimi (karar 114): model için kısa, kararlı ve
/// tekdüze. View'sız saf fonksiyonlar — test edilir.
enum OrchestratorToolFormat {
    /// Tek mesaj metninin üst sınırı — uzun cevaplar bağlamı doldurmasın.
    static let maxTextLength = 2_000
    /// Araç çağrısı / sonucu satırının üst sınırı.
    static let maxToolLineLength = 240
    /// Transkripti olmayan terminalde döndürülen ekran satırı sayısı.
    static let screenLineCount = 80

    static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    /// Terminal durumunun model dili (araç açıklamasındaki küme).
    static func status(_ status: TerminalStatus, isAwaitingDecision: Bool) -> String {
        if isAwaitingDecision { return "awaiting-decision" }
        switch status {
        case .working: return "working"
        case .waitingUnseen: return "needs-attention"
        case .waitingFocused, .waitingSeen: return "waiting"
        case .idle: return "idle"
        case .error: return "error"
        }
    }

    /// "just now" / "4m ago" / "2h ago" / "3d ago".
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "just now"
        case ..<3_600: return "\(seconds / 60)m ago"
        case ..<86_400: return "\(seconds / 3_600)h ago"
        default: return "\(seconds / 86_400)d ago"
        }
    }

    static func header(for meta: TerminalMeta, status: String) -> String {
        "Terminal \"\(meta.displayTitle)\" (\(status)) at \(meta.repoPath)"
    }

    /// Son `limit` METİNLİ mesaj ve aralarındaki araç satırları. Yalnız
    /// tool_result taşıyan kayıtlar sayılmaz (Claude her araç sonucunu ayrı
    /// bir user kaydı olarak yazar — sayılsaydı limit araç gürültüsüyle dolardı).
    static func transcript(_ messages: [ChatMessage], limit: Int) -> String {
        var lines: [String] = []
        var textual = 0
        for message in messages.reversed() {
            let rendered = render(message)
            guard !rendered.lines.isEmpty else { continue }
            if rendered.hasText {
                guard textual < limit else { break }
                textual += 1
            }
            lines.insert(contentsOf: rendered.lines, at: 0)
        }
        return lines.isEmpty ? "(no messages yet)" : lines.joined(separator: "\n")
    }

    private static func render(_ message: ChatMessage) -> (lines: [String], hasText: Bool) {
        var lines: [String] = []
        var hasText = false
        for block in message.blocks {
            switch block {
            case let .text(text, _):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                hasText = true
                lines.append("[\(message.role.rawValue)] \(truncated(trimmed, to: maxTextLength))")
            case let .toolCall(name, preview, _):
                lines.append("  · tool \(name) \(truncated(singleLine(preview), to: maxToolLineLength))")
            case let .toolResult(output, isError):
                let label = isError ? "error" : "result"
                lines.append("  · \(label): \(truncated(singleLine(output), to: maxToolLineLength))")
            case .imageRef, .subagentGroup, .unknown:
                continue
            }
        }
        return (lines, hasText)
    }

    /// Ekranın son satırları; sondaki boş satırlar atılır.
    static func screenTail(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n").map { line in
            String(line.reversed().drop(while: \.isWhitespace).reversed())
        }
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        return lines.suffix(screenLineCount).joined(separator: "\n")
    }

    static func truncated(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "… (truncated)"
    }

    private static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ⏎ ")
    }
}
