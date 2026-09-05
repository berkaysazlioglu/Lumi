import Foundation
import IOKit.pwr_mgt
import LumiKit

/// IOKit power assertion'ı ile sistem uykusunu engeller (karar 43).
///
/// Orca `caffeinate -i -s` çalıştırır; burada aynı etki çocuk süreç olmadan
/// iki assertion'la kurulur: `PreventUserIdleSystemSleep` (`-i`) ve
/// `PreventSystemSleep` (`-s`, yalnız adaptörde etkilidir). Ekran uykusuna
/// karışılmaz.
@MainActor
public final class IOKitSleepAssertion: SleepAsserting {
    private var assertionIDs: [IOPMAssertionID] = []

    public init() {}

    public var isPreventingSleep: Bool { !assertionIDs.isEmpty }

    @discardableResult
    public func setPreventingSleep(_ prevent: Bool, reason: String) -> Bool {
        if prevent == isPreventingSleep { return true }
        guard prevent else {
            release()
            return true
        }
        let types = [
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            kIOPMAssertionTypePreventSystemSleep as CFString,
        ]
        var created: [IOPMAssertionID] = []
        for type in types {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                type, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &id
            )
            if result == kIOReturnSuccess { created.append(id) }
        }
        assertionIDs = created
        return !created.isEmpty
    }

    private func release() {
        for id in assertionIDs { IOPMAssertionRelease(id) }
        assertionIDs = []
    }

    deinit {
        for id in assertionIDs { IOPMAssertionRelease(id) }
    }
}
