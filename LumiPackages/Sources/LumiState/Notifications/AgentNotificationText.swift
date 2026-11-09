import Foundation
import LumiKit

/// Bildirim metinleri (karar 145) — saf, test edilebilir.
///
/// - Başlık: chat'in adı (`displayTitle`).
/// - Alt başlık: `<checkout> · Claude finished` / `needs input` / `failed`.
/// - Gövde: ajanın son mesajı (markdown işaretleri ayıklanmış, tek satır,
///   `bodyLimit` karakter); yoksa duruma göre kısa açıklama.
public enum AgentNotificationText {
    public static let titleLimit = 80
    public static let bodyLimit = 180

    public static func title(displayTitle: String, provider: AgentProvider?) -> String {
        let plain = collapsed(displayTitle)
        return truncated(plain.isEmpty ? agentLabel(provider) : plain, to: titleLimit)
    }

    public static func subtitle(checkout: String, provider: AgentProvider?, kind: AgentNotification.Kind) -> String {
        "\(checkout) · \(agentLabel(provider)) \(statusText(kind))"
    }

    public static func body(kind: AgentNotification.Kind, lastMessage: String?, provider: AgentProvider?) -> String {
        if kind != .needsInput, let lastMessage {
            let plain = plainText(lastMessage)
            if !plain.isEmpty { return truncated(plain, to: bodyLimit) }
        }
        switch kind {
        case .finished: return "\(agentLabel(provider)) finished its turn."
        case .failed: return "\(agentLabel(provider)) stopped with an error."
        case .needsInput: return "Waiting for your permission or answer."
        }
    }

    public static func agentLabel(_ provider: AgentProvider?) -> String {
        switch provider {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case nil: return "Agent"
        }
    }

    static func statusText(_ kind: AgentNotification.Kind) -> String {
        switch kind {
        case .finished: return "finished"
        case .failed: return "failed"
        case .needsInput: return "needs input"
        }
    }

    /// Markdown'ı bildirim satırına indirger: kod blokları (çitler ve
    /// içerikleri) düşer, başlık/madde işaretleri ve vurgu karakterleri
    /// ayıklanır, boşluklar tek boşluğa çöker.
    static func plainText(_ markdown: String) -> String {
        var lines: [String] = []
        var isInCodeBlock = false
        for line in markdown.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                isInCodeBlock.toggle()
            } else if !isInCodeBlock {
                lines.append(strippedLinePrefix(line))
            }
        }
        let joined = lines.joined(separator: " ")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
        return collapsed(joined)
    }

    private static func strippedLinePrefix(_ line: String) -> String {
        var trimmed = Substring(line.trimmingCharacters(in: .whitespaces))
        while trimmed.first == "#" || trimmed.first == ">" { trimmed = trimmed.dropFirst() }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { trimmed = trimmed.dropFirst(2) }
        return String(trimmed)
    }

    static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Karakter (grafem) sınırında keser — emoji/birleşik harf bölünmez.
    static func truncated(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = text.prefix(limit - 1).trimmingCharacters(in: .whitespaces)
        return head + "…"
    }
}
