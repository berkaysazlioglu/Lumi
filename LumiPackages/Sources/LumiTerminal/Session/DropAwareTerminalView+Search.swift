import AppKit
import LumiKit
import SwiftTerm

/// Terminal aramasının görünüm başına durumu (karar 144).
struct TerminalSearchState {
    /// `nil` → arama kapalı (ya da sorgu boş/geçersiz): içerik değişimi tarama tetiklemez.
    var compiled: TerminalSearchMatcher.Compiled?
    var matches: [TerminalSearchMatch] = []
    var activeIndex: Int?
    var isCapped = false
    var rescanTask: Task<Void, Never>?

    var activeMatch: TerminalSearchMatch? {
        activeIndex.flatMap { matches.indices.contains($0) ? matches[$0] : nil }
    }

    var summary: TerminalSearchSummary {
        TerminalSearchSummary(activeIndex: activeIndex, count: matches.count, isCapped: isCapped)
    }
}

// MARK: - Terminal içi arama (karar 144 — Orca `TerminalSearch` paritesi)

extension DropAwareTerminalView {
    /// Çıktı akarken yeniden sayım en fazla bu sıklıkta yapılır. Vurgular
    /// beklemez: satırlar kaydırmadan bağımsız tutulduğu için mevcut
    /// eşleşmeler her beslemede anında yeni görünür alana oturur.
    static let searchRescanInterval: Duration = .milliseconds(250)

    /// Sorguyu buffer'ın tamamında (scrollback dahil) çalıştırır; etkin
    /// eşleşme görünür değilse ona kaydırır.
    func runSearch(_ query: TerminalSearchQuery, step: TerminalSearchStep) -> TerminalSearchSummary {
        guard let compiled = TerminalSearchMatcher.compile(query) else {
            endSearch()
            return .empty
        }
        let previous = searchState.activeMatch?.start
        searchState.compiled = compiled
        rescanMatches()
        let terminal = getTerminal()
        searchState.activeIndex = TerminalSearchNavigation.select(
            step,
            positions: searchState.matches.map(\.start),
            active: previous,
            visibleRows: TerminalSearchBuffer.visibleRows(of: terminal)
        )
        revealActiveMatch(in: terminal)
        refreshSearchHighlights()
        return searchState.summary
    }

    func endSearch() {
        searchState.rescanTask?.cancel()
        searchState = TerminalSearchState()
        searchBuffer.reset()
        searchHighlight.spans = []
    }

    /// PTY çıktısı işlendi (ya da ızgara yeniden boyutlandı): vurgular hemen
    /// kayar, sayım kısılmış bir yeniden taramayla tazelenir.
    func noteSearchContentChanged() {
        guard searchState.compiled != nil else { return }
        refreshSearchHighlights()
        scheduleSearchRescan()
    }

    /// Kaydırma / boyut değişimi: yalnız vurguların yeri değişir.
    func noteSearchViewportChanged() {
        guard searchState.compiled != nil else { return }
        refreshSearchHighlights()
    }

    /// Test gözlemi: görünür alandaki vurgular.
    var searchHighlightSpans: [TerminalSearchHighlightView.Span] { searchHighlight.spans }

    // MARK: - Tarama

    private func rescanMatches() {
        searchState.rescanTask?.cancel()
        searchState.rescanTask = nil
        guard let compiled = searchState.compiled else { return }
        let found = searchBuffer.matches(for: compiled, in: getTerminal())
        searchState.matches = found.matches
        searchState.isCapped = found.isCapped
    }

    private func scheduleSearchRescan() {
        guard searchState.rescanTask == nil else { return }
        searchState.rescanTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.searchRescanInterval)
            guard !Task.isCancelled, let self else { return }
            self.rescanAfterContentChange()
        }
    }

    /// İçerik değişince etkin eşleşme yerinde kalır; satırı yeniden yazıldıysa
    /// sonrakine geçer. Görünür alan kaydırılmaz — kullanıcı çıktıyı izliyor.
    private func rescanAfterContentChange() {
        let before = searchState.summary
        let previous = searchState.activeMatch?.start
        rescanMatches()
        let positions = searchState.matches.map(\.start)
        searchState.activeIndex = previous.flatMap { positions.firstIndex(of: $0) }
            ?? TerminalSearchNavigation.select(
                .incremental,
                positions: positions,
                active: previous,
                visibleRows: TerminalSearchBuffer.visibleRows(of: getTerminal())
            )
        refreshSearchHighlights()
        if searchState.summary != before {
            onSearchResultsChanged?(searchState.summary)
        }
    }

    // MARK: - Görünüm

    /// Etkin eşleşme görünür alanın dışındaysa ortaya gelecek şekilde kaydırır.
    /// Alternatif ekranda (tam ekran TUI) scrollback yoktur.
    private func revealActiveMatch(in terminal: Terminal) {
        guard let row = searchState.activeMatch?.start.row, !terminal.isCurrentBufferAlternate else { return }
        let visible = TerminalSearchBuffer.visibleRows(of: terminal)
        guard !visible.contains(row) else { return }
        scrollTo(row: row - terminal.buffer.totalLinesTrimmed - terminal.rows / 2)
    }

    private func refreshSearchHighlights() {
        let visible = TerminalSearchBuffer.visibleRows(of: getTerminal())
        var spans: [TerminalSearchHighlightView.Span] = []
        for (index, match) in searchState.matches.enumerated() {
            for span in match.spans where visible.contains(span.row) {
                spans.append(.init(
                    row: span.row - visible.lowerBound,
                    columns: span.columns,
                    isActive: index == searchState.activeIndex
                ))
            }
        }
        searchHighlight.cellSize = cellSize
        searchHighlight.spans = spans
    }
}
