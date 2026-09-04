import Foundation
import LumiKit

/// Paylaşılan `ConfigServicing` fake'i.
/// `updateConfig`/`updateUIState` gerçekten saklar — store'ların diskle
/// uzlaşma davranışı (1.16) ancak yazımı hatırlayan bir çift ile test edilebilir.
/// `emit(_:)` ile `ConfigEvent` sürülebilir (ConfigSideEffectCoordinator testleri).
public actor FakeConfigService: ConfigServicing {
    private var storedConfig = AppConfig.defaults
    private var storedUIState = UIState.defaults
    private let broadcaster = EventBroadcaster<ConfigEvent>()
    /// `events()` kaç kez çağrıldı — abonelik penceresini beklemek için
    /// (tüketici Task çalışana kadar `emit` düşer; plan 5.6'nın test tarafı).
    private let subscriptions = SubscriptionCounter()
    public private(set) var uiStateUpdateCount = 0
    public private(set) var configUpdateCount = 0
    public private(set) var flushCount = 0
    private var firstRun = false
    /// Yazım hatası yolunu (optimistik değerin geri alınması) sürmek için.
    private var updateConfigError: LumiError?
    /// Yalnız İLK `updateUIState` çağrısına uygulanan gecikme: actor reentrancy
    /// ile yazım sırasının bozulmasını (1.17) deterministik olarak sürer.
    private var firstUIStateWriteDelay: Duration?

    public init() {}

    public func seed(_ state: UIState) {
        storedUIState = state
    }

    public func seed(_ config: AppConfig) {
        storedConfig = config
    }

    public func setFirstRun(_ value: Bool) {
        firstRun = value
    }

    public func setUpdateConfigError(_ error: LumiError?) {
        updateConfigError = error
    }

    public func setFirstUIStateWriteDelay(_ delay: Duration?) {
        firstUIStateWriteDelay = delay
    }

    /// Koordinatör/store'lara config event'i sürer.
    public nonisolated func emit(_ event: ConfigEvent) {
        broadcaster.send(event)
    }

    /// `old`/`new` çiftini tek çağrıda gönderen kısayol.
    public nonisolated func emitConfigChange(old: AppConfig, new: AppConfig) {
        broadcaster.send(.configChanged(old: old, new: new))
    }

    public func config() -> AppConfig { storedConfig }

    public func updateConfig(_ mutate: @Sendable (inout AppConfig) -> Void) throws {
        if let updateConfigError {
            throw updateConfigError
        }
        var copy = storedConfig
        mutate(&copy)
        storedConfig = copy
        configUpdateCount += 1
    }

    public func uiState() -> UIState { storedUIState }

    public func updateUIState(_ mutate: @Sendable (inout UIState) -> Void) async {
        if let delay = firstUIStateWriteDelay {
            firstUIStateWriteDelay = nil
            try? await Task.sleep(for: delay)
        }
        var state = storedUIState
        mutate(&state)
        storedUIState = state
        uiStateUpdateCount += 1
    }

    public func isFirstRun() -> Bool { firstRun }

    public func flushPendingWrites() { flushCount += 1 }

    /// Bir tüketici `events()` çağırana kadar `emit` edilen event'ler düşer.
    public nonisolated var subscriberCount: Int { subscriptions.value }

    public nonisolated func events() -> AsyncStream<ConfigEvent> {
        let stream = broadcaster.stream()
        subscriptions.increment()
        return stream
    }
}
