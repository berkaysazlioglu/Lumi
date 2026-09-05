import Foundation
import LumiKit
import Observation

/// "Keep computer awake" durumu (karar 43; Orca `AgentAwakeService` paritesi).
///
/// Mod `SettingsStore`'dan (kalıcı), çalışan ajan sayısı `TerminalListStore`'dan
/// türer; ikisinin bileşimi `shouldPreventSleep`. Store bu türevi gözlemleyip
/// (`withObservationTracking`) yalnız değiştiğinde IOKit assertion'ını açar
/// ya da kapatır — her terminal event'inde sistem çağrısı yapılmaz.
@Observable
@MainActor
public final class ComputerAwakeStore: StoreLifecycle {
    @ObservationIgnored private let terminals: TerminalListStore
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let assertion: any SleepAsserting
    @ObservationIgnored private var isObserving = false
    /// Assertion kurulamadıysa (IOKit hata döndü) rozet pasif görünür.
    public private(set) var assertionFailed = false

    public init(terminals: TerminalListStore, settings: SettingsStore, assertion: any SleepAsserting) {
        self.terminals = terminals
        self.settings = settings
        self.assertion = assertion
    }

    // MARK: - Türevler

    public var mode: ComputerAwakeMode { settings.current.computerAwakeMode }

    public var workingAgentCount: Int {
        terminals.terminals.filter { $0.status == .working }.count
    }

    public var shouldPreventSleep: Bool {
        mode.isActive(workingAgentCount: workingAgentCount)
    }

    /// Alt bar segmentinin gösterdiği durum: engel gerçekten kuruluysa aktif.
    public var status: ComputerAwakeStatus {
        ComputerAwakeStatus(mode: mode, isActive: shouldPreventSleep && !assertionFailed)
    }

    // MARK: - Eylemler

    public func setMode(_ mode: ComputerAwakeMode) {
        settings.apply { $0.computerAwakeMode = mode }
    }

    // MARK: - Yaşam döngüsü

    public func start() {
        guard !isObserving else { return }
        isObserving = true
        sync()
        observe()
    }

    public func stop() {
        isObserving = false
        assertion.setPreventingSleep(false, reason: Self.reason)
    }

    /// Türev ile assertion'ı hizalar; test edilebilir tek nokta.
    public func sync() {
        let ok = assertion.setPreventingSleep(shouldPreventSleep, reason: Self.reason)
        assertionFailed = shouldPreventSleep && !ok
    }

    private func observe() {
        withObservationTracking {
            _ = shouldPreventSleep
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isObserving else { return }
                self.sync()
                self.observe()
            }
        }
    }

    static let reason = "Lumi: keep computer awake while agents run"
}
