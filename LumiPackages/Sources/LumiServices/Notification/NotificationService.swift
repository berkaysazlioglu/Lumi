import Foundation
import LumiKit

/// Bildirim teslim servisi (karar 145). Bildirimin ne zaman doğacağına
/// `AgentNotificationCoordinator` karar verir (tur başına bir kez, tekrar
/// yok); burada yalnız teslim kuralları uygulanır:
///
/// | Durum                                   | Toast | OS bildirimi |
/// |-----------------------------------------|-------|--------------|
/// | Ayarda kapalı tür                        | –     | –            |
/// | Terminal ekranda ve odakta              | –     | –            |
/// | Pencere odaklı                          | ✓     | –            |
/// | Pencere odakta değil                    | ✓     | ✓ (cooldown) |
///
/// Cooldown: aynı checkout için `cooldown` içinde ikinci OS bildirimi gitmez
/// (birden çok terminal aynı anda bittiğinde ses yağmuru olmasın).
public final class NotificationService: NotificationServicing {
    public static let defaultCooldown: TimeInterval = 5

    private let presenter: any NotificationPresenting
    private let cooldown: TimeInterval
    private let now: @MainActor () -> Date
    private let broadcaster = EventBroadcaster<NotificationEvent>(label: "notifications")
    private var settings: NotificationSettings
    private var windowFocused = true
    private var permissionRequested = false
    private var lastDelivered: [String: Date] = [:]

    public init(
        presenter: any NotificationPresenting,
        settings: NotificationSettings = .defaults,
        cooldown: TimeInterval = NotificationService.defaultCooldown,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.presenter = presenter
        self.settings = settings
        self.cooldown = cooldown
        self.now = now
    }

    public func requestPermissionIfNeeded() async {
        guard !permissionRequested else { return }
        permissionRequested = true
        _ = await presenter.requestAuthorization()
    }

    public func updateSettings(_ settings: NotificationSettings) {
        self.settings = settings
    }

    public func setWindowFocused(_ focused: Bool) {
        windowFocused = focused
    }

    public func deliver(_ notification: AgentNotification) {
        guard settings.allows(notification.kind) else { return }
        guard !(notification.isTerminalFocused && windowFocused) else { return }
        broadcaster.send(.attention(notification))
        guard !windowFocused, claimCooldown(notification.groupKey) else { return }
        presenter.present(
            id: notification.terminalID.description,
            title: notification.title,
            subtitle: notification.subtitle,
            body: notification.body,
            sound: settings.sound
        )
    }

    public func dismiss(_ id: TerminalID) {
        presenter.removeDelivered(id: id.description)
    }

    public func terminalRemoved(_ id: TerminalID) {
        presenter.removeDelivered(id: id.description)
    }

    public func events() -> AsyncStream<NotificationEvent> {
        broadcaster.stream()
    }

    /// Bildirim tıklaması köprüsü — presenter implementasyonu (app target)
    /// tıklamayı buraya iletir.
    public func notificationClicked(terminalID: TerminalID) {
        broadcaster.send(.clicked(terminalID))
    }

    /// Anahtar bekleme süresinde değilse süreyi başlatır ve true döner.
    private func claimCooldown(_ key: String) -> Bool {
        let current = now()
        lastDelivered = lastDelivered.filter { current.timeIntervalSince($0.value) < cooldown }
        guard lastDelivered[key] == nil else { return false }
        lastDelivered[key] = current
        return true
    }
}
