import Foundation
import LumiKit
import LumiServices
import LumiState
import os

/// Teşhis izi (karar 83).
private let notificationLogger = LumiLog.logger("notifications")

/// Bildirim köprüleri (karar 145): terminal olayları →
/// `AgentNotificationCoordinator` (tur başına bir bildirim) →
/// `NotificationServicing` (teslim) → toast / terminal odağı.
@MainActor
final class NotificationAssembly: FeatureAssembly {
    let bootstrapPhase = BootstrapPhase.config

    private var services: (any ServiceRegistry)!
    private var shared: SharedStores!
    private var coordinator: AgentNotificationCoordinator?
    private var notificationBridge: Task<Void, Never>?
    /// Bildirim alt başlığındaki checkout adı Projects ağacından okunur —
    /// repo/workspace store'ları repo assembly'sinde doğar (`.repo` fazı);
    /// etiket bildirim anında çözülür, o an ikisi de hazırdır.
    private let repo: RepoFeatureAssembly?

    init(repo: RepoFeatureAssembly? = nil) {
        self.repo = repo
    }

    func build(services: any ServiceRegistry, shared: SharedStores) {
        self.services = services
        self.shared = shared
        coordinator = AgentNotificationCoordinator(
            service: services.terminal,
            terminals: shared.terminals,
            notifications: services.notifications,
            transcripts: services.terminalTranscripts,
            checkoutLabel: { [repo, navigation = shared.navigation] path in
                guard let workspaces = repo?.workspaceStore, let repos = repo?.repoStore else {
                    return (path as NSString).lastPathComponent
                }
                return CheckoutLabel.make(for: path, workspaces: workspaces, repos: repos, navigation: navigation)
            }
        )
    }

    func start() async {
        let config = await services.config.config()
        services.notifications.updateSettings(config.notifications)
        coordinator?.start()
        startNotificationBridge()
        await services.notifications.requestPermissionIfNeeded()
    }

    func configDidChange(old: AppConfig, new: AppConfig) {
        guard old.notifications != new.notifications else { return }
        services.notifications.updateSettings(new.notifications)
    }

    func shutdown() async {
        coordinator?.stop()
        notificationBridge?.cancel()
        notificationBridge = nil
    }

    // MARK: - Köprüler

    /// Bildirim event'leri → store'lar.
    private func startNotificationBridge() {
        guard notificationBridge == nil else { return }
        let stream = services.notifications.events()
        notificationBridge = Task { @MainActor [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .clicked(let id):
                    // Minimize istisnası: bildirim tıklaması restore + focus
                    notificationLogger.log("notification clicked \(LumiLog.short(id), privacy: .public)")
                    self.shared.terminals.restoreAndFocus(id)
                case .attention(let notification):
                    self.shared.toasts.show(
                        .bell,
                        title: notification.title,
                        message: "\(notification.subtitle)\n\(notification.body)",
                        terminalID: notification.terminalID
                    )
                }
            }
        }
    }
}
