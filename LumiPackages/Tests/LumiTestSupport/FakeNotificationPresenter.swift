import Foundation
import LumiKit

/// `NotificationPresenting` fake'i — OS bildirim katmanının dikiş yeri.
/// Protokol `Sendable` ama metodları @MainActor; kayıt yine de kilitlidir ki
/// `requestAuthorization` (nonisolated) ile aynı depoya güvenle yazılabilsin.
public final class FakeNotificationPresenter: NotificationPresenting, @unchecked Sendable {
    public struct Presented: Equatable, Sendable {
        public let id: String
        public let title: String
        public let body: String

        public init(id: String, title: String, body: String) {
            self.id = id
            self.title = title
            self.body = body
        }
    }

    private let lock = NSLock()
    private var presentedRecords: [Presented] = []
    private var removedRecords: [String] = []
    private var authorizationResult = true
    private var authorizationCalls = 0

    public init(authorizationResult: Bool = true) {
        self.authorizationResult = authorizationResult
    }

    public var presented: [Presented] { lock.withLock { presentedRecords } }
    public var removed: [String] { lock.withLock { removedRecords } }
    public var authorizationRequestCount: Int { lock.withLock { authorizationCalls } }

    public func requestAuthorization() async -> Bool {
        lock.withLock {
            authorizationCalls += 1
            return authorizationResult
        }
    }

    @MainActor
    public func present(id: String, title: String, body: String) {
        lock.withLock { presentedRecords.append(Presented(id: id, title: title, body: body)) }
    }

    @MainActor
    public func removeDelivered(id: String) {
        lock.withLock { removedRecords.append(id) }
    }
}
