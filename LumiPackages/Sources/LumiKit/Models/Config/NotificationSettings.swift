import Foundation

/// `config.json` → `notifications`: görülmemiş/görülmüş bekleyen terminaller
/// için tekrarlayan hatırlatma ayarları.
///
/// **Persistence yalnız `ConfigCodec` üzerinden — karar 9.**
public struct NotificationSettings: Sendable, Equatable {
    public var unseenEnabled: Bool
    public var unseenIntervalMinutes: Int
    public var seenEnabled: Bool
    public var seenIntervalMinutes: Int

    public static let defaults = NotificationSettings(
        unseenEnabled: true,
        unseenIntervalMinutes: 1,
        seenEnabled: true,
        seenIntervalMinutes: 5
    )

    public init(
        unseenEnabled: Bool,
        unseenIntervalMinutes: Int,
        seenEnabled: Bool,
        seenIntervalMinutes: Int
    ) {
        self.unseenEnabled = unseenEnabled
        self.unseenIntervalMinutes = unseenIntervalMinutes
        self.seenEnabled = seenEnabled
        self.seenIntervalMinutes = seenIntervalMinutes
    }
}
