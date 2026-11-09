import Foundation

/// `config.json` → `notifications` (karar 145).
///
/// Bildirim tur başına bir kez gider (ajan turunu bitirdi / hata verdi / karar
/// bekliyor); tekrarlayan hatırlatma yoktur.
///
/// `unseen*`/`seen*` alanları karar 145 öncesinin tekrar ayarlarıdır — artık
/// hiçbir davranışı sürmez, yalnız diskteki değerleri aynen geri yazılsın diye
/// taşınır (karar 9: `notifications` sözlüğü bütün olarak yazılır).
///
/// **Persistence yalnız `ConfigCodec` üzerinden — karar 9.**
public struct NotificationSettings: Sendable, Equatable {
    /// Ajan turunu bitirdi ya da hatayla durdu.
    public var agentFinished: Bool
    /// Ajan izin ya da cevap bekliyor.
    public var needsInput: Bool
    /// OS bildirimi sistem sesiyle gelir.
    public var sound: Bool

    // Eski (karar 145 öncesi) tekrar ayarları — kullanılmaz, korunur.
    public var unseenEnabled: Bool
    public var unseenIntervalMinutes: Int
    public var seenEnabled: Bool
    public var seenIntervalMinutes: Int

    public static let defaults = NotificationSettings(
        agentFinished: true,
        needsInput: true,
        sound: true,
        unseenEnabled: true,
        unseenIntervalMinutes: 1,
        seenEnabled: true,
        seenIntervalMinutes: 5
    )

    public init(
        agentFinished: Bool = true,
        needsInput: Bool = true,
        sound: Bool = true,
        unseenEnabled: Bool = true,
        unseenIntervalMinutes: Int = 1,
        seenEnabled: Bool = true,
        seenIntervalMinutes: Int = 5
    ) {
        self.agentFinished = agentFinished
        self.needsInput = needsInput
        self.sound = sound
        self.unseenEnabled = unseenEnabled
        self.unseenIntervalMinutes = unseenIntervalMinutes
        self.seenEnabled = seenEnabled
        self.seenIntervalMinutes = seenIntervalMinutes
    }

    /// Bu tür bildirim ayarlarda açık mı?
    public func allows(_ kind: AgentNotification.Kind) -> Bool {
        switch kind {
        case .finished, .failed: return agentFinished
        case .needsInput: return needsInput
        }
    }
}
