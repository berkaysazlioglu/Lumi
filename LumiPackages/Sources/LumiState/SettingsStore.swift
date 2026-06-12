import Foundation
import LumiKit
import Observation

/// Settings aynası (karar 3: macOS anlık uygulama — draft/Save/Escape YOK).
/// Her kontrol değişikliği anında config'e yazılır; yan etkiler
/// ConfigSideEffectCoordinator'ın equality-diff'inden akar.
@Observable
@MainActor
public final class SettingsStore {
    public private(set) var current: AppConfig = .defaults

    @ObservationIgnored private let config: any ConfigServicing
    @ObservationIgnored private let toasts: ToastStore
    @ObservationIgnored private var consumeTask: Task<Void, Never>?

    public init(config: any ConfigServicing, toasts: ToastStore) {
        self.config = config
        self.toasts = toasts
    }

    public func start() {
        guard consumeTask == nil else { return }
        consumeTask = Task { @MainActor [weak self, config] in
            let stream = await config.events()
            self?.current = await config.config()
            for await event in stream {
                guard case .configChanged(_, let new) = event else { continue }
                self?.current = new
            }
        }
    }

    public func stop() {
        consumeTask?.cancel()
        consumeTask = nil
    }

    /// Modal her açılışta taze config çeker (spec/22 — mount'ta değil).
    public func refresh() async {
        current = await config.config()
    }

    public func apply(_ mutate: @escaping @Sendable (inout AppConfig) -> Void) {
        var copy = current
        mutate(&copy)
        current = copy // UI anında yansır; kalıcı yazım + yan etkiler aşağıda
        Task { @MainActor in
            await toasts.reporting {
                try await self.config.updateConfig(mutate)
            }
        }
    }

    // MARK: - Alan bazlı kolaylıklar

    public func setProjectsRoot(_ path: String) {
        apply { $0.projectsRoot = path }
    }

    public func setProvider(_ provider: AgentProvider) {
        apply { $0.aiProvider = provider }
    }

    public func setMaxTerminals(_ count: Int) {
        let clamped = min(max(count, 1), 20)
        apply { $0.maxTerminals = clamped }
    }

    public func setTerminalFontSize(_ size: Int) {
        let clamped = min(max(size, 10), 24)
        apply { $0.terminalFontSize = clamped }
    }

    public func setTerminalFontSmoothing(_ enabled: Bool) {
        apply { $0.terminalFontSmoothing = enabled }
    }

    public func setNotifications(_ settings: NotificationSettings) {
        apply { $0.notifications = settings }
    }

    public func addAdditionalPath(_ path: String, type: AdditionalPath.PathType) {
        let entry = AdditionalPath(id: UUID().uuidString, path: path, type: type)
        apply { $0.additionalPaths.append(entry) }
    }

    public func removeAdditionalPath(id: String) {
        apply { $0.additionalPaths.removeAll { $0.id == id } }
    }
}
