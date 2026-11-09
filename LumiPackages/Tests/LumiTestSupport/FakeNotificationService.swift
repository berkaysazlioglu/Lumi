import Foundation
import LumiKit

/// `NotificationServicing` fake'i (@MainActor). Ayar güncellemeleri ve teslim
/// edilen bildirimler kaydedilir; `emit(_:)` ile bildirim event'i sürülür.
@MainActor
public final class FakeNotificationService: NotificationServicing {
    private let broadcaster = EventBroadcaster<NotificationEvent>()

    public private(set) var permissionRequestCount = 0
    public private(set) var settingsUpdates: [NotificationSettings] = []
    public private(set) var windowFocusCalls: [Bool] = []
    public private(set) var delivered: [AgentNotification] = []
    public private(set) var dismissed: [TerminalID] = []
    public private(set) var removedTerminals: [TerminalID] = []

    public init() {}

    public func requestPermissionIfNeeded() async {
        permissionRequestCount += 1
    }

    public func updateSettings(_ settings: NotificationSettings) {
        settingsUpdates.append(settings)
    }

    public func setWindowFocused(_ focused: Bool) {
        windowFocusCalls.append(focused)
    }

    public func deliver(_ notification: AgentNotification) {
        delivered.append(notification)
    }

    public func dismiss(_ id: TerminalID) {
        dismissed.append(id)
    }

    public func terminalRemoved(_ id: TerminalID) {
        removedTerminals.append(id)
    }

    public func events() -> AsyncStream<NotificationEvent> {
        broadcaster.stream()
    }

    public func emit(_ event: NotificationEvent) {
        broadcaster.send(event)
    }
}
