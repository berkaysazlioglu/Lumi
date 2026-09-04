import Foundation
import LumiKit

/// `NotificationServicing` fake'i (@MainActor). Ayar güncellemeleri ve status
/// köprüsü çağrıları kaydedilir; `emit(_:)` ile bildirim event'i sürülür.
@MainActor
public final class FakeNotificationService: NotificationServicing {
    public struct StatusChange: Equatable, Sendable {
        public let id: TerminalID
        public let repoName: String
        public let status: TerminalStatus

        public init(id: TerminalID, repoName: String, status: TerminalStatus) {
            self.id = id
            self.repoName = repoName
            self.status = status
        }
    }

    private let broadcaster = EventBroadcaster<NotificationEvent>()

    public private(set) var permissionRequestCount = 0
    public private(set) var settingsUpdates: [NotificationSettings] = []
    public private(set) var windowFocusCalls: [Bool] = []
    public private(set) var statusChanges: [StatusChange] = []
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

    public func handleStatusChange(id: TerminalID, repoName: String, status: TerminalStatus) {
        statusChanges.append(StatusChange(id: id, repoName: repoName, status: status))
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
