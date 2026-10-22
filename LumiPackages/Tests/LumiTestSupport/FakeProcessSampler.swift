import Foundation
import LumiKit

/// `ProcessSampling` sahtesi: verilen tabloyu döndürür, çağrı sayar.
public actor FakeProcessSampler: ProcessSampling {
    public private(set) var table: ProcessTable?
    public private(set) var sampleCount = 0

    public init(table: ProcessTable? = .empty) {
        self.table = table
    }

    public func setTable(_ table: ProcessTable?) {
        self.table = table
    }

    public func sampleProcessTable() async -> ProcessTable? {
        sampleCount += 1
        return table
    }
}

/// `SleepAsserting` sahtesi: durum + çağrı kaydı.
@MainActor
public final class FakeSleepAssertion: SleepAsserting {
    public private(set) var isPreventingSleep = false
    public private(set) var calls: [(prevent: Bool, reason: String)] = []
    public var shouldFail = false

    public init() {}

    @discardableResult
    public func setPreventingSleep(_ prevent: Bool, reason: String) -> Bool {
        calls.append((prevent, reason))
        if shouldFail { return false }
        isPreventingSleep = prevent
        return true
    }
}

/// `LidSleepControlling` sahtesi (karar 122): sistem ayarı + sıradaki sonuç.
public final class FakeLidSleepControl: LidSleepControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var _sleepDisabled: Bool?
    private var _nextChange: LidSleepChange = .applied
    private var _onBattery = false
    private var _changes: [Bool] = []

    public init(sleepDisabled: Bool? = false) {
        _sleepDisabled = sleepDisabled
    }

    /// Sistemin gördüğü değer; `nil` = okunamıyor.
    public var sleepDisabled: Bool? {
        get { lock.withLock { _sleepDisabled } }
        set { lock.withLock { _sleepDisabled = newValue } }
    }

    public var nextChange: LidSleepChange {
        get { lock.withLock { _nextChange } }
        set { lock.withLock { _nextChange = newValue } }
    }

    public var onBattery: Bool {
        get { lock.withLock { _onBattery } }
        set { lock.withLock { _onBattery = newValue } }
    }

    /// İstenen değişiklikler (sonuçtan bağımsız).
    public var changes: [Bool] { lock.withLock { _changes } }

    public func isSleepDisabled() async -> Bool? { sleepDisabled }

    public func setSleepDisabled(_ disabled: Bool) async -> LidSleepChange {
        lock.withLock {
            _changes.append(disabled)
            if _nextChange == .applied { _sleepDisabled = disabled }
            return _nextChange
        }
    }

    public func isOnBatteryPower() -> Bool { onBattery }
}
