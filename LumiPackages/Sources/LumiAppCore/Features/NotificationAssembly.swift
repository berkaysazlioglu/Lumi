import Foundation
import LumiKit
import LumiServices
import LumiState

/// Bildirim köprüleri (refactor 3.3): terminal status → OS bildirimi ve
/// bildirim event'leri → store'lar.
@MainActor
final class NotificationAssembly: FeatureAssembly {
    let bootstrapPhase = BootstrapPhase.config

    private var services: (any ServiceRegistry)!
    private var shared: SharedStores!
    private var statusBridge: Task<Void, Never>?
    private var notificationBridge: Task<Void, Never>?

    func build(services: any ServiceRegistry, shared: SharedStores) {
        self.services = services
        self.shared = shared
    }

    func start() async {
        let config = await services.config.config()
        services.notifications.updateSettings(config.notifications)
        startStatusBridge()
        startNotificationBridge()
        await services.notifications.requestPermissionIfNeeded()
    }

    func configDidChange(old: AppConfig, new: AppConfig) {
        guard old.notifications != new.notifications else { return }
        services.notifications.updateSettings(new.notifications)
    }

    func shutdown() async {
        statusBridge?.cancel()
        statusBridge = nil
        notificationBridge?.cancel()
        notificationBridge = nil
    }

    // MARK: - Köprüler

    /// Terminal status event'leri → `NotificationServicing` (onChange köprüsü).
    private func startStatusBridge() {
        guard statusBridge == nil else { return }
        let stream = services.terminal.events()
        statusBridge = Task { @MainActor [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .statusChanged(let id, let status):
                    let repoName = self.shared.terminals.meta(for: id)
                        .map { ($0.repoPath as NSString).lastPathComponent } ?? "Terminal"
                    self.services.notifications.handleStatusChange(
                        id: id, repoName: repoName, status: status
                    )
                case .exited(let id, _):
                    // Cleanup sözleşmesi: interval timer'lar iptal edilir (sızıntı yok)
                    self.services.notifications.terminalRemoved(id)
                case .spawned, .titleChanged, .awaitingDecisionChanged, .bell,
                     .writeFailed, .viewFocused, .stalled:
                    break
                }
            }
        }
    }

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
                    self.shared.terminals.restoreAndFocus(id)
                case .bell(let id, let repoName):
                    self.shared.toasts.show(
                        .bell,
                        title: repoName,
                        message: NotificationService.waitingBody,
                        terminalID: id
                    )
                }
            }
        }
    }
}
