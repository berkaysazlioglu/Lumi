import Foundation
import LumiKit
import Observation

/// Settings aynası (karar 3: macOS anlık uygulama — draft/Save/Escape YOK).
/// Her kontrol değişikliği anında config'e yazılır; yan etkiler
/// ConfigSideEffectCoordinator'ın equality-diff'inden akar.
@Observable
@MainActor
public final class SettingsStore: StoreLifecycle {
    public private(set) var current: AppConfig = .defaults

    @ObservationIgnored private let config: any ConfigServicing
    @ObservationIgnored private let toasts: ToastStore
    @ObservationIgnored private let consumer = EventConsumer()
    /// Monoton yazım sürümü: geç dönen disk okuması daha yeni bir apply'ı ezmesin.
    @ObservationIgnored private var applyVersion = 0

    public init(config: any ConfigServicing, toasts: ToastStore) {
        self.config = config
        self.toasts = toasts
    }

    public func start() {
        // Stream Task'tan ÖNCE (plan 5.6): abonelik start() dönmeden kurulur.
        consumer.start(
            config.events(),
            prologue: { [weak self, config] in self?.current = await config.config() }
        ) { [weak self] event in
            guard case .configChanged(_, let new) = event else { return }
            self?.current = new
        }
    }

    public func stop() {
        consumer.stop()
    }

    /// Modal her açılışta taze config çeker (mount'ta değil).
    public func refresh() async {
        current = await config.config()
    }

    public func apply(_ mutate: @escaping @Sendable (inout AppConfig) -> Void) {
        var copy = current
        mutate(&copy)
        current = copy // UI anında yansır; kalıcı yazım + yan etkiler aşağıda
        applyVersion += 1
        let version = applyVersion
        Task { @MainActor in
            await toasts.reporting {
                try await self.config.updateConfig(mutate)
            }
            // Optimistik değer diskle uzlaşır (servis normalize edebilir, yazım
            // başarısız olabilir; `updated == old` ise event de gelmez).
            // Araya yeni bir apply girdiyse bayat okuma onu ezmez.
            let fresh = await self.config.config()
            guard version == self.applyVersion else { return }
            self.current = fresh
        }
    }

    // MARK: - Bölüm bazlı güncellemeler (yazım anında TAZE `current`'tan okur)

    /// View'ın body-anı snapshot'ına yazması ayar clobber'ına yol açıyordu:
    /// mutasyon burada, yazım anındaki güncel değerin üzerine uygulanır.
    public func updateNotifications(
        _ mutate: @escaping @Sendable (inout NotificationSettings) -> Void
    ) {
        apply { mutate(&$0.notifications) }
    }

    public func updateSessionTrigger(
        _ mutate: @escaping @Sendable (inout SessionTrigger) -> Void
    ) {
        apply { mutate(&$0.sessionTrigger) }
    }

    public func updateUsageAutoRefresh(
        _ mutate: @escaping @Sendable (inout UsageAutoRefresh) -> Void
    ) {
        apply { mutate(&$0.usageAutoRefresh) }
    }

    // MARK: - Alan bazlı kolaylıklar

    public func setProjectsRoot(_ path: String) {
        apply { $0.projectsRoot = path }
    }

    public func setProvider(_ provider: AgentProvider) {
        apply { $0.aiProvider = provider }
    }

    public func setTerminalFontSize(_ size: Int) {
        let clamped = min(max(size, 10), 24)
        apply { $0.terminalFontSize = clamped }
    }

    public func setTerminalFontFamily(_ family: String) {
        apply { $0.terminalFontFamily = family }
    }

    public func setTerminalCursorStyle(_ shape: TerminalCursorShape) {
        apply { $0.terminalCursorStyle = shape.rawValue }
    }

    public func setTerminalCursorBlink(_ blink: Bool) {
        apply { $0.terminalCursorBlink = blink }
    }

    public func setNotifications(_ settings: NotificationSettings) {
        apply { $0.notifications = settings }
    }

    public func setAutoMinimizeOnSend(_ enabled: Bool) {
        apply { $0.autoMinimizeOnSend = enabled }
    }

    public func setSessionTrigger(_ trigger: SessionTrigger) {
        apply { $0.sessionTrigger = trigger }
    }

    public func setUsageAutoRefresh(_ settings: UsageAutoRefresh) {
        apply { $0.usageAutoRefresh = settings }
    }

    public func setUsageIndicators(_ indicators: UsageIndicators) {
        apply { $0.usageIndicators = indicators }
    }

    public func addAdditionalPath(_ path: String, type: AdditionalPath.PathType) {
        let entry = AdditionalPath(id: UUID().uuidString, path: path, type: type)
        apply { $0.additionalPaths.append(entry) }
    }

    public func removeAdditionalPath(id: String) {
        apply { $0.additionalPaths.removeAll { $0.id == id } }
    }
}
