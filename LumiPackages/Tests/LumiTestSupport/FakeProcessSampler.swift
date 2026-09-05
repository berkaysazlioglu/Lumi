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
