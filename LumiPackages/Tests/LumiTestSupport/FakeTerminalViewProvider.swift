import AppKit
import Foundation
import LumiKit

/// `TerminalViewProviding` fake'i: attach/detach çağrılarını sırasıyla kaydeder
/// (SwiftUI reparenting yarışlarının karakterizasyonu için).
@MainActor
public final class FakeTerminalViewProvider: TerminalViewProviding {
    public struct Call: Equatable, Sendable {
        public let id: TerminalID
        public let container: ObjectIdentifier

        public init(id: TerminalID, container: ObjectIdentifier) {
            self.id = id
            self.container = container
        }
    }

    public private(set) var attachCalls: [Call] = []
    public private(set) var detachCalls: [Call] = []
    /// `refreshAttachedViews` çağrı sayacı (fullscreen onarım köprüsünün kanıtı).
    public private(set) var refreshCallCount = 0

    public init() {}

    /// Hâlâ bağlı sayılan terminaller (attach - detach farkı).
    public var attachedIDs: [TerminalID] {
        var live: [TerminalID] = []
        for call in attachCalls where !detachCalls.contains(call) {
            live.append(call.id)
        }
        return live
    }

    public func attachView(for id: TerminalID, into container: NSView) {
        attachCalls.append(Call(id: id, container: ObjectIdentifier(container)))
    }

    public func detachView(for id: TerminalID, from container: NSView) {
        detachCalls.append(Call(id: id, container: ObjectIdentifier(container)))
    }

    public func refreshAttachedViews() {
        refreshCallCount += 1
    }
}
