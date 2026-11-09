import AppKit
import LumiKit

/// Karar 144: terminal içi arama motoru — kayıtlı canlı view'a iner.
/// Arama yalnız Lumi'nin kendi terminal view'ında (`DropAwareTerminalView`)
/// vardır; başka bir view kayıtlıysa istek "arama yok" döner.
extension TerminalViewRegistry: TerminalSearching {
    @discardableResult
    public func search(_ id: TerminalID, query: TerminalSearchQuery, step: TerminalSearchStep) -> TerminalSearchSummary {
        guard let view = searchableView(id) else { return .empty }
        return view.runSearch(query, step: step)
    }

    public func clearSearch(_ id: TerminalID) {
        searchableView(id)?.endSearch()
    }

    private func searchableView(_ id: TerminalID) -> DropAwareTerminalView? {
        view(for: id) as? DropAwareTerminalView
    }
}
