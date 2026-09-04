import Foundation

/// Günlük zamanlanmış oturum tetikleyicisi (`~/.lumi/config.json` →
/// `sessionTrigger`). Uygulama açıkken her gün `hour:minute` saatinde, bekleyen
/// bir Claude oturumuna `prompt` enjekte ederek 5 saatlik kullanım penceresini
/// başlatır. Saat kullanıcının yerel takvimine göredir.
///
/// **Persistence yalnız `ConfigCodec` üzerinden — karar 9.**
public struct SessionTrigger: Sendable, Equatable {
    public var enabled: Bool
    /// 0–23 (yerel saat).
    public var hour: Int
    /// 0–59.
    public var minute: Int
    /// Enjekte edilen prompt; boşsa "hello"ya düşer.
    public var prompt: String

    public static let defaultPrompt = "hello"

    public static let defaults = SessionTrigger(
        enabled: false,
        hour: 9,
        minute: 0,
        prompt: defaultPrompt
    )

    public init(enabled: Bool, hour: Int, minute: Int, prompt: String) {
        self.enabled = enabled
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.prompt = prompt
    }

    /// Enjeksiyonda kullanılacak güvenli prompt (boş/whitespace → default).
    public var effectivePrompt: String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultPrompt : trimmed
    }
}
