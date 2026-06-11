import Foundation

public enum NotificationEvent: Sendable, Equatable {
    /// Kullanıcı OS bildirimine tıkladı → terminal odaklanmalı.
    /// Minimize edilmiş terminalin otomatik odak alabildiği TEK yol (spec/21 §6).
    case clicked(TerminalID)
    /// Status-güdümlü toast sinyali — pencere odağından bağımsız her zaman gönderilir
    /// (Electron'daki `terminal:bell(id, repoName)` kanalının karşılığı).
    case bell(TerminalID, repoName: String)
}

/// OS bildirim sunumunun dikiş yeri. UNUserNotificationCenter bundle'lı app
/// gerektirir (SPM executable'da çöker) — gerçek implementasyon app target'ta
/// (Faz 6), skeleton log-presenter, testler fake kullanır.
public protocol NotificationPresenting: Sendable {
    func requestAuthorization() async -> Bool
    @MainActor func present(id: String, title: String, body: String)
    @MainActor func removeDelivered(id: String)
}

/// Status-makinesi-güdümlü bildirim servisi (design/02 §7, spec/13 §4).
@MainActor
public protocol NotificationServicing: AnyObject {
    func requestPermissionIfNeeded() async
    func updateSettings(_ settings: NotificationSettings)
    /// Pencere odaklıyken native OS bildirimi gönderilmez (focus guard).
    func setWindowFocused(_ focused: Bool)
    func handleStatusChange(id: TerminalID, repoName: String, status: TerminalStatus)
    /// Exit-cleanup sözleşmesi (spec/10 §9): interval timer'ı iptal eder —
    /// çağrılmazsa timer sızar.
    func terminalRemoved(_ id: TerminalID)
    func events() -> AsyncStream<NotificationEvent>
}
