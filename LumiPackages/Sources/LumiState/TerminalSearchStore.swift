import Foundation
import LumiKit
import Observation

/// Terminal içi arama çubuklarının durumu (karar 144 — Orca `TerminalSearch`).
///
/// Her terminalin kendi çubuğu vardır; kapatılan çubuğun sorgusu ve seçenekleri
/// korunur, ⌘F ile yeniden açılınca arama aynı sorguyla yeniden koşar (Orca'da
/// bileşen kapanınca da durumunu tutar). Buffer'ı taramak, vurgulamak ve
/// kaydırmak motorun (`TerminalSearching`) işidir.
@MainActor
@Observable
public final class TerminalSearchStore {
    public struct Session: Equatable {
        public var isOpen = false
        public var query = TerminalSearchQuery()
        public var summary = TerminalSearchSummary.empty
        /// ⌘F her basıldığında artar: çubuk alanı odaklar ve metni seçer
        /// (çubuk zaten açıkken de).
        public var focusRequest = 0
        /// Görünümün yerine getirdiği son istek. İstek tek seferliktir: kart
        /// yeniden doğduğunda (grid ⇄ maximize) çubuk odağı terminalden çalmaz.
        public var handledFocusRequest = 0

        public var isFocusRequested: Bool { focusRequest > handledFocusRequest }

        /// Sayaç metni — `0/0`, `No results`, `3/14`, `1000+`.
        public var statusText: String {
            summary.statusText(hasQuery: query.requestText != nil)
        }
    }

    public private(set) var sessions: [TerminalID: Session] = [:]

    @ObservationIgnored private let engine: any TerminalSearching
    @ObservationIgnored private let terminals: TerminalListStore

    public init(engine: any TerminalSearching, terminals: TerminalListStore) {
        self.engine = engine
        self.terminals = terminals
        engine.onSearchResultsChanged = { [weak self] id, summary in
            self?.applyRecount(summary, for: id)
        }
    }

    public func session(for id: TerminalID) -> Session? {
        sessions[id]
    }

    public func isOpen(_ id: TerminalID) -> Bool {
        sessions[id]?.isOpen == true
    }

    // MARK: - Intent'ler

    /// ⌘F: çubuğu açar; açıksa alanı yeniden odaklar.
    public func open(_ id: TerminalID) {
        pruneClosedTerminals()
        var session = sessions[id] ?? Session()
        session.focusRequest += 1
        let wasOpen = session.isOpen
        session.isOpen = true
        sessions[id] = session
        if !wasOpen { run(.incremental, for: id) }
    }

    /// Çubuk alanı odaklandı — bekleyen ⌘F isteği düşer.
    public func didFocusField(_ id: TerminalID) {
        guard let request = sessions[id]?.focusRequest else { return }
        sessions[id]?.handledFocusRequest = request
    }

    /// Esc / ✕: vurgular kalkar, klavye odağı terminale döner. Sorgu korunur.
    public func close(_ id: TerminalID) {
        guard var session = sessions[id], session.isOpen else { return }
        session.isOpen = false
        session.summary = .empty
        sessions[id] = session
        engine.clearSearch(id)
        terminals.focus(id)
    }

    public func setText(_ text: String, for id: TerminalID) {
        guard sessions[id]?.query.text != text else { return }
        sessions[id]?.query.text = text
        run(.incremental, for: id)
    }

    public func toggleCaseSensitive(_ id: TerminalID) {
        sessions[id]?.query.isCaseSensitive.toggle()
        run(.incremental, for: id)
    }

    public func toggleRegex(_ id: TerminalID) {
        sessions[id]?.query.isRegex.toggle()
        run(.incremental, for: id)
    }

    /// Enter / ⌘G — sonraki eşleşme (sarar).
    public func next(_ id: TerminalID) {
        run(.next, for: id)
    }

    /// ⇧Enter / ⇧⌘G — önceki eşleşme (sarar).
    public func previous(_ id: TerminalID) {
        run(.previous, for: id)
    }

    /// ⌘G / ⇧⌘G (Orca): eşleşmeye geçer ve klavye odağını terminale verir —
    /// bulunan yerde yazmaya devam edilir, çubuk açık kalır.
    public func navigateFromShortcut(_ id: TerminalID, forward: Bool) {
        guard isOpen(id), sessions[id]?.query.requestText != nil else { return }
        run(forward ? .next : .previous, for: id)
        terminals.focus(id)
    }

    // MARK: - Motor

    private func run(_ step: TerminalSearchStep, for id: TerminalID) {
        guard let session = sessions[id], session.isOpen else { return }
        let summary = engine.search(id, query: session.query, step: step)
        sessions[id]?.summary = summary
    }

    /// Çıktı akarken yeniden yapılan sayım; kapalı çubuğa yazılmaz.
    private func applyRecount(_ summary: TerminalSearchSummary, for id: TerminalID) {
        guard isOpen(id) else { return }
        sessions[id]?.summary = summary
    }

    /// Kapanmış terminallerin kayıtları düşer (karar 144 — sızıntı yok).
    private func pruneClosedTerminals() {
        sessions = sessions.filter { terminals.meta(for: $0.key) != nil }
    }
}

public extension TerminalSearchStore {
    /// Canlı terminali olmayan bağlamlar (önizleme, kabuk testleri): çubuk
    /// açılır ama hiçbir şey bulunmaz.
    convenience init(terminals: TerminalListStore) {
        self.init(engine: InertTerminalSearch(), terminals: terminals)
    }
}

/// Emülatörsüz arama motoru — her sorgu "eşleşme yok" döner.
@MainActor
private final class InertTerminalSearch: TerminalSearching {
    var onSearchResultsChanged: ((TerminalID, TerminalSearchSummary) -> Void)?

    func search(_ id: TerminalID, query: TerminalSearchQuery, step: TerminalSearchStep) -> TerminalSearchSummary {
        .empty
    }

    func clearSearch(_ id: TerminalID) {}
}
