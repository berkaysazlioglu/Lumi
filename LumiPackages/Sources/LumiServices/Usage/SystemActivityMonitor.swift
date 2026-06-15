import CoreGraphics
import Foundation
import LumiKit

/// `ActivityMonitoring`'in sistem implementasyonu (karar 20). CoreGraphics'in
/// `CGEventSource.secondsSinceLastEventType` çağrısıyla son HID girdisinden bu
/// yana geçen süreyi döndürür. Bu sorgu salt-okunur idle ölçümüdür — event-tap
/// gibi Accessibility/Input-Monitoring izni GEREKTİRMEZ.
public struct SystemActivityMonitor: ActivityMonitoring {
    public init() {}

    public func secondsSinceUserInput() -> TimeInterval {
        // kCGAnyInputEventType (= ~0): klavye, fare, trackpad — tüm girdi türleri.
        let anyInput = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}
