import Foundation

/// Kullanıcı aktivitesi sınırı (karar 20). Usage auto-refresh'in "yalnızca
/// kullanıcı aktifse tazele" kapısı bu soyutlamayı kullanır; somut implementasyon
/// (LumiServices `SystemActivityMonitor`) CoreGraphics'in sistem-geneli idle
/// sayacını sarar. Soyutlama, store'un fake bir monitörle test edilmesini sağlar.
public protocol ActivityMonitoring: Sendable {
    /// Sistem genelinde son kullanıcı HID girdisinden (klavye/fare/trackpad) bu
    /// yana geçen saniye. Mac uykudayken process askıda olduğundan sorgulanmaz.
    func secondsSinceUserInput() -> TimeInterval
}
