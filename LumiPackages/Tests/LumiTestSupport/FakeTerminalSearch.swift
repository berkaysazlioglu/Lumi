import Foundation
import LumiKit

/// `TerminalSearching` fake'i (karar 144): çağrıları kaydeder, sonucu
/// testin verdiği özetten döner; yeniden sayımı `emitRecount` sürer.
@MainActor
public final class FakeTerminalSearch: TerminalSearching {
    public struct Call: Equatable {
        public let id: TerminalID
        public let query: TerminalSearchQuery
        public let step: TerminalSearchStep

        public init(id: TerminalID, query: TerminalSearchQuery, step: TerminalSearchStep) {
            self.id = id
            self.query = query
            self.step = step
        }
    }

    public var onSearchResultsChanged: ((TerminalID, TerminalSearchSummary) -> Void)?
    /// Sıradaki `search` çağrılarının döneceği özet.
    public var nextSummary = TerminalSearchSummary(activeIndex: 0, count: 1)
    public private(set) var calls: [Call] = []
    public private(set) var clearedIDs: [TerminalID] = []

    public init() {}

    public func search(_ id: TerminalID, query: TerminalSearchQuery, step: TerminalSearchStep) -> TerminalSearchSummary {
        calls.append(Call(id: id, query: query, step: step))
        return query.requestText == nil ? .empty : nextSummary
    }

    public func clearSearch(_ id: TerminalID) {
        clearedIDs.append(id)
    }

    public func emitRecount(_ summary: TerminalSearchSummary, for id: TerminalID) {
        onSearchResultsChanged?(id, summary)
    }
}
