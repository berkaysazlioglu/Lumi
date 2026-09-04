import Foundation
import LumiKit

/// Paylaşılan config fake'i (WorkspaceStore + SettingsStore testleri).
/// `updateConfig`/`updateUIState` gerçekten saklar — store'ların diskle
/// uzlaşma davranışı (1.16) ancak yazımı hatırlayan bir çift ile test edilebilir.
actor FakeConfigService: ConfigServicing {
    private var storedConfig = AppConfig.defaults
    private var storedUIState = UIState.defaults
    private(set) var uiStateUpdateCount = 0
    private(set) var configUpdateCount = 0
    /// Yazım hatası yolunu (optimistik değerin geri alınması) sürmek için.
    private var updateConfigError: LumiError?
    /// Yalnız İLK `updateUIState` çağrısına uygulanan gecikme: actor reentrancy
    /// ile yazım sırasının bozulmasını (1.17) deterministik olarak sürer.
    private var firstUIStateWriteDelay: Duration?

    func seed(_ state: UIState) {
        storedUIState = state
    }

    func seed(_ config: AppConfig) {
        storedConfig = config
    }

    func setUpdateConfigError(_ error: LumiError?) {
        updateConfigError = error
    }

    func setFirstUIStateWriteDelay(_ delay: Duration?) {
        firstUIStateWriteDelay = delay
    }

    func config() -> AppConfig { storedConfig }

    func updateConfig(_ mutate: @Sendable (inout AppConfig) -> Void) throws {
        if let updateConfigError {
            throw updateConfigError
        }
        var copy = storedConfig
        mutate(&copy)
        storedConfig = copy
        configUpdateCount += 1
    }

    func uiState() -> UIState { storedUIState }

    func updateUIState(_ mutate: @Sendable (inout UIState) -> Void) async {
        if let delay = firstUIStateWriteDelay {
            firstUIStateWriteDelay = nil
            try? await Task.sleep(for: delay)
        }
        var state = storedUIState
        mutate(&state)
        storedUIState = state
        uiStateUpdateCount += 1
    }

    func isFirstRun() -> Bool { false }
    func flushPendingWrites() {}

    func events() -> AsyncStream<ConfigEvent> {
        AsyncStream { $0.finish() }
    }
}
