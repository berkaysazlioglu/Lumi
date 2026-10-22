import Foundation
import LumiKit
import Observation

/// "Keep computer awake" durumu (karar 43; Orca `AgentAwakeService` paritesi).
///
/// Mod `SettingsStore`'dan (kalıcı), çalışan ajan sayısı `TerminalListStore`'dan
/// türer; ikisinin bileşimi `shouldPreventSleep`. Store bu türevi gözlemleyip
/// (`withObservationTracking`) yalnız değiştiğinde IOKit assertion'ını açar
/// ya da kapatır — her terminal event'inde sistem çağrısı yapılmaz.
///
/// Karar 122: moddan bağımsız "Also when lid is closed" anahtarı sistem
/// geneli `pmset disablesleep` ayarını yönetir. Doğruluk kaynağı sistemdir;
/// Lumi'nin açtığı (`lidSleepDisabledByLumi`) çıkışta geri alınır, çıkışta
/// geri alınamayan kalıntı bir sonraki açılışta işaretlenir.
@Observable
@MainActor
public final class ComputerAwakeStore: StoreLifecycle {
    @ObservationIgnored private let terminals: TerminalListStore
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let assertion: any SleepAsserting
    @ObservationIgnored private let lidSleep: any LidSleepControlling
    @ObservationIgnored private var isObserving = false
    @ObservationIgnored private var lidStartTask: Task<Void, Never>?
    /// Assertion kurulamadıysa (IOKit hata döndü) rozet pasif görünür.
    public private(set) var assertionFailed = false
    /// Sistemin son okunan `SleepDisabled` değeri.
    public private(set) var isLidAwake = false
    public private(set) var isLidLeftover = false
    public private(set) var isLidChangePending = false
    public private(set) var isOnBattery = false
    public private(set) var lidErrorMessage: String?

    public init(
        terminals: TerminalListStore,
        settings: SettingsStore,
        assertion: any SleepAsserting,
        lidSleep: any LidSleepControlling
    ) {
        self.terminals = terminals
        self.settings = settings
        self.assertion = assertion
        self.lidSleep = lidSleep
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

    private var ownsLidSleep: Bool { settings.current.lidSleepDisabledByLumi }

    public var lidStatus: LidAwakeStatus {
        LidAwakeStatus(
            isOn: isLidAwake, isOwnedByLumi: ownsLidSleep, isLeftover: isLidLeftover,
            isPending: isLidChangePending, isOnBattery: isOnBattery, errorMessage: lidErrorMessage
        )
    }

    // MARK: - Eylemler

    public func setMode(_ mode: ComputerAwakeMode) {
        settings.apply { $0.computerAwakeMode = mode }
    }

    /// Sistemden taze okur (popover her açıldığında). Lumi'nin açtığı ayar
    /// dışarıdan kapatıldıysa sahiplik düşer.
    public func refreshLidState() async {
        isOnBattery = lidSleep.isOnBatteryPower()
        guard let disabled = await lidSleep.isSleepDisabled() else { return }
        isLidAwake = disabled
        if !disabled {
            isLidLeftover = false
            if ownsLidSleep { settings.apply { $0.lidSleepDisabledByLumi = false } }
        }
    }

    /// Yönetici şifresi sorarak ayarı değiştirir; iptal sessizdir.
    public func setLidAwake(_ isOn: Bool) async {
        guard !isLidChangePending else { return }
        isLidChangePending = true
        lidErrorMessage = nil
        defer { isLidChangePending = false }
        switch await lidSleep.setSleepDisabled(isOn) {
        case .applied:
            isLidAwake = isOn
            isLidLeftover = false
            settings.apply { $0.lidSleepDisabledByLumi = isOn }
        case .cancelled:
            break
        case .failed(let message):
            lidErrorMessage = message
        }
        isOnBattery = lidSleep.isOnBatteryPower()
    }

    /// Çıkışta Lumi'nin açtığı ayarı geri alır. Kullanıcı şifreyi iptal ederse
    /// sahiplik kalır ve bir sonraki açılışta kalıntı olarak işaretlenir.
    public func restoreLidSleep() async {
        lidStartTask?.cancel()
        guard ownsLidSleep, await lidSleep.isSleepDisabled() == true else { return }
        if await lidSleep.setSleepDisabled(false) == .applied {
            isLidAwake = false
            settings.apply { $0.lidSleepDisabledByLumi = false }
        }
    }

    // MARK: - Yaşam döngüsü

    public func start() {
        guard !isObserving else { return }
        isObserving = true
        sync()
        observe()
        lidStartTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshLidState()
            guard !Task.isCancelled else { return }
            self.isLidLeftover = self.isLidAwake && self.ownsLidSleep
        }
    }

    public func stop() {
        isObserving = false
        lidStartTask?.cancel()
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
