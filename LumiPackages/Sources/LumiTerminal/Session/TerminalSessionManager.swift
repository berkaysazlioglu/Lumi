import AppKit
import Foundation
import LumiKit
import SwiftTerm

/// Terminal alt sisteminin servis yüzü: `TerminalServicing` implementasyonu
/// (design/01 §7). Sıralı koleksiyon tutar (karar 11), limit yalnız burada
/// uygulanır ve aşımı görünür hatadır (karar 5).
@MainActor
public final class TerminalSessionManager: TerminalServicing {
    public static let defaultMaxTerminals = 12

    public let viewRegistry = TerminalViewRegistry()

    private var sessions: [TerminalSession] = []
    private var maxTerminals = TerminalSessionManager.defaultMaxTerminals
    private var spawnCounter = 0
    private let broadcaster = EventBroadcaster<TerminalEvent>()
    /// Font (aile + boyut). Yeni spawn'lara uygulanır VE canlı olarak tüm açık
    /// terminallere yansır (SwiftTerm `terminalView.font` setter zinciri resize +
    /// SIGWINCH + redraw üretir — fontSmoothing ile aynı canlı-uygulama deseni).
    public var font: NSFont {
        didSet {
            guard font != oldValue else { return }
            sessions.forEach { $0.setFont(font) }
        }
    }
    /// macOS stem-darkening. Font boyutunun aksine canlı uygulanır: CG draw
    /// path'i her çizimde okur, redraw yeterli (Metal backend kullanılmıyor).
    public var fontSmoothing = false {
        didSet {
            guard fontSmoothing != oldValue else { return }
            sessions.forEach { $0.setFontSmoothing(fontSmoothing) }
        }
    }
    /// Renk teması. Canlı uygulanır: yeni spawn'lar + tüm açık terminaller.
    public var theme: TerminalTheme = .lumi {
        didSet {
            guard theme != oldValue else { return }
            sessions.forEach { $0.applyTheme(theme) }
        }
    }
    /// Caret şekli + blink (SwiftTerm CursorStyle'a çözülmüş). Canlı uygulanır.
    public var cursorStyle: CursorStyle = .blinkBlock {
        didSet {
            sessions.forEach { $0.setCursorStyle(cursorStyle) }
        }
    }
    private var keyMonitor: Any?
    private var mouseMonitor: Any?

    /// Terminal NSView'ına tıklayınca store odağının senkronlanması için köprü
    /// (Electron'daki karta-tıkla → setActiveTerminal paritesi, spec/20 §9).
    public var onTerminalViewFocused: ((TerminalID) -> Void)?

    public init(font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)) {
        self.font = font
        installNaturalEditingMonitor()
        installFocusClickMonitor()
    }

    private func installFocusClickMonitor() {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            // First responder tıklama dispatch'i SONRASI oluşur — bir tur ertele
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let view = event.window?.firstResponder as? DropAwareTerminalView,
                      let id = self.viewRegistry.terminalID(for: view) else { return }
                self.onTerminalViewFocused?(id)
            }
            return event
        }
    }

    /// SwiftTerm keyDown'ı sealed olduğundan doğal-düzenleme eşlemeleri
    /// (Option+Backspace → ^W vb.) dispatch'ten önce local monitor'la uygulanır.
    /// Yalnız first responder bir Lumi terminal view'ıyken devreye girer.
    private func installNaturalEditingMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let view = event.window?.firstResponder as? DropAwareTerminalView,
                  let bytes = NaturalEditingKeyMap.bytes(for: event) else {
                return event
            }
            view.send(bytes)
            return nil
        }
    }

    public var terminals: [TerminalMeta] {
        sessions.map(\.meta)
    }

    @discardableResult
    public func spawn(repoPath: String, task: String?, command: String?) throws -> TerminalMeta {
        guard sessions.count < maxTerminals else {
            throw LumiError.terminalLimitReached(max: maxTerminals)
        }
        spawnCounter += 1
        // Karar 23: claude komutuna --session-id enjeksiyonu (veya mevcut
        // flag'ten çıkarım) — ID meta'da taşınır, quit'te resume için persist edilir.
        let prepared = ClaudeSessionCommand.prepare(command: command)
        let session = try TerminalSession(
            repoPath: repoPath,
            name: "Terminal \(spawnCounter)",
            task: task,
            claudeSessionID: prepared.sessionID,
            font: font
        )
        session.delegate = self
        session.setFontSmoothing(fontSmoothing)
        // Spawn-time: manager'ın güncel tema + cursor değerlerini uygula
        // (DropAwareTerminalView'daki hardcoded lumi default'unu ezer).
        session.applyTheme(theme)
        session.setCursorStyle(cursorStyle)
        sessions.append(session)
        viewRegistry.register(
            view: session.terminalView,
            for: session.id,
            onVisibilityChange: { [weak session] visible in
                session?.setHidden(!visible)
                // Görünür olunca TUI'yi yeniden çizmeye zorla (boyut değişmese bile) —
                // grid↔maximize round-trip'inde boş kalan kartın onarımı.
                if visible { session?.requestRepaint() }
            },
            onRedraw: { [weak session] in
                // Frame gerçek boyuta oturunca (tab değişimi sonrası reassert)
                // buffer'dan poke'suz tam çizim — boş kart onarımının ikinci yarısı.
                session?.redrawFromBuffer()
            }
        )
        broadcaster.send(.spawned(session.meta))
        if let command = prepared.command {
            session.scheduleLaunchCommand(command)
        }
        return session.meta
    }

    public func write(id: TerminalID, text: String) throws {
        guard let session = session(for: id) else {
            throw LumiError.terminalNotFound(id)
        }
        session.write(text)
    }

    public func kill(id: TerminalID) throws {
        guard let session = session(for: id) else {
            throw LumiError.terminalNotFound(id)
        }
        session.terminate()
    }

    public func killAll() {
        sessions.forEach { $0.terminate() }
    }

    public func resize(id: TerminalID, cols: Int, rows: Int) {
        session(for: id)?.requestResize(cols: cols, rows: rows)
    }

    public func setFocused(_ id: TerminalID?) {
        for session in sessions {
            session.setTabFocused(session.id == id)
        }
    }

    public func setWindowFocused(_ focused: Bool) {
        sessions.forEach { $0.setWindowFocused(focused) }
    }

    public func setMaxTerminals(_ n: Int) {
        maxTerminals = max(1, n)
    }

    public func events() -> AsyncStream<TerminalEvent> {
        broadcaster.stream()
    }

    public func outputStream(id: TerminalID) -> AsyncStream<String>? {
        session(for: id)?.outputStream()
    }

    private func session(for id: TerminalID) -> TerminalSession? {
        sessions.first { $0.id == id }
    }
}

// MARK: - Oturum delegasyonu

extension TerminalSessionManager: TerminalSessionDelegate {
    func session(_ session: TerminalSession, didChangeStatus status: TerminalStatus) {
        guard isRegistered(session) else { return }
        broadcaster.send(.statusChanged(session.id, status))
    }

    func session(_ session: TerminalSession, didChangeAwaitingDecision awaiting: Bool) {
        guard isRegistered(session) else { return }
        broadcaster.send(.awaitingDecisionChanged(session.id, awaiting))
    }

    func session(_ session: TerminalSession, didChangeTitle title: String) {
        guard isRegistered(session) else { return }
        broadcaster.send(.titleChanged(session.id, title))
    }

    func sessionDidBell(_ session: TerminalSession) {
        guard isRegistered(session) else { return }
        broadcaster.send(.bell(session.id))
    }

    func session(_ session: TerminalSession, didExitWithCode code: Int32) {
        // Exit-cleanup sırası (spec/10 §9): önce kayıttan düş — stale push imkânsızlaşır —
        // sonra exit yayınla
        sessions.removeAll { $0.id == session.id }
        viewRegistry.unregister(session.id)
        broadcaster.send(.exited(session.id, code: code))
    }

    private func isRegistered(_ session: TerminalSession) -> Bool {
        sessions.contains { $0 === session }
    }
}
