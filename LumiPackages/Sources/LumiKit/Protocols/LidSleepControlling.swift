import Foundation

/// `pmset disablesleep` değişikliğinin sonucu (karar 122).
public enum LidSleepChange: Sendable, Equatable {
    case applied
    /// Kullanıcı yönetici şifresi dialogunu kapattı.
    case cancelled
    case failed(String)
}

/// Kapak kapalıyken uykuyu engelleme (karar 122). IOKit assertion'ları
/// kapağı kapsamaz; tek yol root isteyen sistem geneli `pmset -a disablesleep`
/// ayarıdır ve süreç ölünce kendiliğinden düşmez.
public protocol LidSleepControlling: Sendable {
    /// `pmset -g`'deki `SleepDisabled`; `nil` = okunamadı.
    func isSleepDisabled() async -> Bool?
    /// Yönetici şifresi sorarak ayarı değiştirir.
    func setSleepDisabled(_ disabled: Bool) async -> LidSleepChange
    /// Mac şu an pilden mi besleniyor (uyarı için).
    func isOnBatteryPower() -> Bool
}
