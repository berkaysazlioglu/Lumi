import Foundation

/// Bir ajan terminalinin tek bir "dikkat" anı (karar 145) — OS bildirimi ve
/// uygulama içi toast aynı içerikten üretilir.
public struct AgentNotification: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Ajan turunu bitirdi (`working` → `waiting*`).
        case finished
        /// Ajan turu hatayla bitti (`working` → `error`).
        case failed
        /// Ajan izin ya da cevap bekliyor.
        case needsInput
    }

    public let terminalID: TerminalID
    public let kind: Kind
    /// Chat'in adı (`TerminalMeta.displayTitle`).
    public let title: String
    /// `<checkout> · Claude finished`.
    public let subtitle: String
    /// Ajanın son mesajı ya da duruma göre kısa açıklama.
    public let body: String
    /// Terminal bildirim anında ekranda ve odaktaydı: hiçbir yüzeyde
    /// gösterilmez.
    public let isTerminalFocused: Bool
    /// Bekleme süresi (cooldown) anahtarı — checkout yolu.
    public let groupKey: String

    public init(
        terminalID: TerminalID,
        kind: Kind,
        title: String,
        subtitle: String,
        body: String,
        isTerminalFocused: Bool,
        groupKey: String
    ) {
        self.terminalID = terminalID
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.isTerminalFocused = isTerminalFocused
        self.groupKey = groupKey
    }
}
