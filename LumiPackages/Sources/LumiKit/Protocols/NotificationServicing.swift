import Foundation

public enum NotificationEvent: Sendable, Equatable {
    /// Kullanıcı OS bildirimine tıkladı → terminal odaklanmalı.
    /// Minimize edilmiş terminalin otomatik odak alabildiği TEK yol.
    case clicked(TerminalID)
    /// Uygulama içi toast sinyali (karar 145) — pencere odağından bağımsız,
    /// yalnız terminal ekranda ve odakta değilken gönderilir.
    case attention(AgentNotification)
}

/// OS bildirim sunumunun dikiş yeri. UNUserNotificationCenter bundle'lı app
/// gerektirir (SPM executable'da çöker) — gerçek implementasyon app target'ta,
/// skeleton log-presenter, testler fake kullanır.
public protocol NotificationPresenting: Sendable {
    func requestAuthorization() async -> Bool
    /// Aynı `id` ile gelen bildirim öncekinin yerini alır.
    @MainActor func present(id: String, title: String, subtitle: String, body: String, sound: Bool)
    @MainActor func removeDelivered(id: String)
}

/// Bildirim teslim servisi (karar 145). Ne zaman bildirim doğacağına
/// `AgentNotificationCoordinator` karar verir; servis ayarları, pencere odağını
/// ve bekleme süresini uygular.
@MainActor
public protocol NotificationServicing: AnyObject {
    func requestPermissionIfNeeded() async
    func updateSettings(_ settings: NotificationSettings)
    /// Pencere odaklıyken native OS bildirimi gönderilmez (yalnız toast).
    func setWindowFocused(_ focused: Bool)
    func deliver(_ notification: AgentNotification)
    /// Terminal yeniden çalıştı ya da görüldü: teslim edilmiş bildirimi kaldırır.
    func dismiss(_ id: TerminalID)
    func terminalRemoved(_ id: TerminalID)
    func events() -> AsyncStream<NotificationEvent>
}
