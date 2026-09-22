import AppKit
import Foundation
import LumiKit
import SwiftTerm
import os

/// Terminal alt sisteminin servis yüzü: `TerminalServicing` implementasyonu
/// (design/01 §7). Sıralı koleksiyon tutar (karar 11); spawn limiti yoktur
/// (karar 29).
@MainActor
public final class TerminalSessionManager: TerminalServicing {
    public let viewRegistry = TerminalViewRegistry()
    /// Teşhis izi (karar 83).
    private static let logger = LumiLog.logger("terminal")

    /// Sıralı oturum kaydı (karar 11). `private(set)`: dışarıdan yalnız okunur —
    /// testler canlı oturumlara uygulanan görünüm ayarlarını buradan doğrular.
    private(set) var sessions: [TerminalSession] = []
    private var spawnCounter = 0
    private let broadcaster = EventBroadcaster<TerminalEvent>(label: "terminal")
    /// Font (aile + boyut). Yeni spawn'lara uygulanır VE canlı olarak tüm açık
    /// terminallere yansır (SwiftTerm `terminalView.font` setter zinciri resize +
    /// SIGWINCH + redraw üretir — cursorStyle ile aynı canlı-uygulama deseni).
    private var font: NSFont
    /// Caret şekli + blink (SwiftTerm CursorStyle'a çözülmüş). Canlı uygulanır.
    private var cursorStyle: CursorStyle = .blinkBlock
    /// Karar 57: düz tıkla açılan link eylemleri (Settings ▸ Terminal).
    private var linkActionsEnabled = true
    /// Odağın tek otoritesi (Faz 4.3/4.9): `setFocused` ile gelen seçim burada
    /// tutulur ki yüzey geçişleri (`setSurfaceState`) odağı yeniden türetmek
    /// yerine aynı kaynaktan okusun — foreground olmak tek başına odak
    /// kazandırmaz.
    private var focusedID: TerminalID?
    /// Karar 45: hook sunucusunun uç noktası; sonraki spawn'ların PTY env'ine
    /// yazılır. `nil` = hook'lar kapalı.
    private var hookEndpoint: AgentHookEndpoint?
    private var launchEnvironments: [AgentProvider: [String: String]] = [:]
    /// Terminal alt sisteminin tek uygulama-seviyesi NSEvent monitörü (refactor 4.7):
    /// klavye eşlemesi, kart odağı, tekerlek/hover. Enjekte edilir ki testler gerçek
    /// bir global monitör kurmadan (ya da kurulumu doğrulayarak) koşabilsin.
    private let eventMonitor: TerminalEventMonitor

    public init(
        font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular),
        eventMonitor: TerminalEventMonitor = TerminalEventMonitor()
    ) {
        self.font = font
        self.eventMonitor = eventMonitor
        eventMonitor.start { [weak self] view in
            self?.noteViewFocused(view)
        }
    }

    /// Terminal NSView'ı first responder oldu (karta tıklama; Electron'daki
    /// karta-tıkla → setActiveTerminal paritesi). Kayıtlı olmayan view sessizce
    /// yok sayılır — bayat first-responder koruması.
    func noteViewFocused(_ view: NSView) {
        guard let id = viewRegistry.terminalID(for: view) else { return }
        broadcaster.send(.viewFocused(id))
    }

    // MARK: - TerminalAppearanceControlling

    /// Font'u canlı tüm oturumlara uygular; sonraki spawn'lar devralır.
    public func applyFont(_ font: NSFont) {
        guard font != self.font else { return }
        self.font = font
        sessions.forEach { $0.setFont(font) }
    }

    /// Caret şekli + blink'i canlı tüm oturumlara uygular; sonraki spawn'lar devralır.
    /// SwiftTerm `CursorStyle` çevirisi burada kalır — çağıran SwiftTerm tanımaz.
    public func applyCursor(shape: TerminalCursorShape, blink: Bool) {
        // Eşitlik kısa devresi YOK: TUI, DECSCUSR ile caret'i ezmiş olabilir —
        // aynı değerin yeniden uygulanması kullanıcı ayarını geri getirir.
        let style = TerminalCursorStyleMapper.swiftTermStyle(shape: shape, blink: blink)
        cursorStyle = style
        sessions.forEach { $0.setCursorStyle(style) }
    }

    /// Karar 57: ayar canlı uygulanır ve sonraki spawn'lar devralır.
    public func applyLinkActions(enabled: Bool) {
        guard linkActionsEnabled != enabled else { return }
        linkActionsEnabled = enabled
        sessions.forEach { $0.setLinkActionsEnabled(enabled) }
    }

    public var terminals: [TerminalMeta] {
        sessions.map(\.meta)
    }

    @discardableResult
    public func spawn(repoPath: String, task: String?, command: String?) throws -> TerminalMeta {
        try spawn(repoPath: repoPath, task: task, command: command, environment: [:])
    }

    @discardableResult
    public func spawn(
        repoPath: String,
        task: String?,
        command: String?,
        environment: [String: String]
    ) throws -> TerminalMeta {
        spawnCounter += 1
        // Karar 23: claude komutuna --session-id enjeksiyonu (veya mevcut
        // flag'ten çıkarım) — ID meta'da taşınır, quit'te resume için persist edilir.
        let prepared = ClaudeSessionCommand.prepare(command: command)
        let provider = AgentProvider.detect(launchCommand: prepared.command)
        var effectiveEnvironment = provider.flatMap { launchEnvironments[$0] } ?? [:]
        effectiveEnvironment.merge(environment) { _, override in override }
        let codexSessionID = provider == .codex
            ? CodexSessionCommand.resumedSessionID(from: prepared.command) : nil
        let session = try TerminalSession(
            repoPath: repoPath,
            name: "Terminal \(spawnCounter)",
            task: task,
            claudeSessionID: prepared.sessionID,
            codexSessionID: codexSessionID,
            codexHome: provider == .codex ? effectiveEnvironment["CODEX_HOME"] : nil,
            provider: provider,
            environment: effectiveEnvironment,
            hookEndpoint: hookEndpoint,
            font: font
        )
        session.delegate = self
        // Spawn-time: manager'ın güncel cursor değerini uygula (palet sabit —
        // DropAwareTerminalView zaten TerminalTheme.lumi uygular).
        session.setCursorStyle(cursorStyle)
        session.setLinkActionsEnabled(linkActionsEnabled)
        // Katman sınırı (Faz 4.1): oturum superview'a dokunmaz; hücre boyutu
        // değişince yeniden yerleşimi registry üzerinden host'tan ister.
        let sessionID = session.id
        session.onLayoutInvalidated = { [weak self] in
            self?.viewRegistry.invalidateLayout(for: sessionID)
        }
        sessions.append(session)
        Self.logger.log(
            "spawn \(LumiLog.short(session.id), privacy: .public) repo=\((repoPath as NSString).lastPathComponent, privacy: .public) command=\(prepared.command != nil) sessions=\(self.sessions.count)"
        )
        viewRegistry.register(
            view: session.terminalView,
            for: session.id,
            onVisibilityChange: { [weak self] visible in
                self?.applyVisibility(visible, for: sessionID)
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
            let live = sessions.map { LumiLog.short($0.id) }.joined(separator: ",")
            Self.logger.log("kill \(LumiLog.short(id), privacy: .public): not found; live=[\(live, privacy: .public)]")
            throw LumiError.terminalNotFound(id)
        }
        Self.logger.log("kill \(LumiLog.short(id), privacy: .public)")
        session.terminate()
    }

    public func killAll() {
        Self.logger.log("killAll \(self.sessions.count)")
        sessions.forEach { $0.terminate() }
    }

    public func processID(for id: TerminalID) -> Int32? {
        session(for: id)?.processID
    }

    public func setAgentHookEndpoint(_ endpoint: AgentHookEndpoint?) {
        Self.logger.log("agent hook endpoint \(endpoint == nil ? "cleared" : "set", privacy: .public)")
        hookEndpoint = endpoint
    }

    public func setLaunchEnvironment(_ environment: [String: String], for provider: AgentProvider) {
        launchEnvironments[provider] = environment
    }

    /// Kapanmış terminalin geç gelen hook'u sessizce düşer.
    public func applyAgentHookEvent(_ event: AgentHookEvent) {
        guard let session = session(for: event.terminalID) else {
            Self.logger.log("hook for unknown terminal \(LumiLog.short(event.terminalID), privacy: .public)")
            return
        }
        session.applyHookEvent(event)
    }

    public func resize(id: TerminalID, cols: Int, rows: Int) {
        session(for: id)?.requestResize(cols: cols, rows: rows)
    }

    public func setFocused(_ id: TerminalID?) {
        focusedID = id
        for session in sessions {
            session.setTabFocused(session.id == id)
        }
        // Durum makinesi odağı ile klavye odağı aynı otoriteden akar: mor çerçeve
        // (activeTerminalID) neyi gösteriyorsa klavye girdisi oraya gitmeli.
        if let id {
            viewRegistry.requestKeyboardFocus(for: id)
        } else {
            viewRegistry.cancelPendingKeyboardFocus()
        }
    }

    /// Faz 4.3 — tek terminalin yüzey durumu. Odak bilgisi manager'ın kendi
    /// otoritesinden (`focusedID`) gelir: `.foreground` yalnız gerçekten seçili
    /// terminale odak geri verir, diğerleri görünür ama odaksız kalır.
    public func setSurfaceState(_ state: TerminalSurfaceState, for id: TerminalID) {
        session(for: id)?.setSurfaceState(state, isFocused: focusedID == id)
    }

    /// Faz 4.3 — toplu yüzey geçişi (route/tab değişimi). `repoPath == nil` ⇒ tümü.
    public func setSurfaceState(_ state: TerminalSurfaceState, in repoPath: String?) {
        for session in sessions where repoPath == nil || session.meta.repoPath == repoPath {
            session.setSurfaceState(state, isFocused: focusedID == session.id)
        }
    }

    /// Registry görünürlük sinyalinin tek yorumu: yüzey durumu + (görünür olunca)
    /// TUI'yi yeniden çizmeye zorlama. Boş kalan kartın onarımı buradan akar —
    /// `requestRepaint` buffer'dan tam çizim + SIGWINCH poke'unu birlikte yapar.
    private func applyVisibility(_ visible: Bool, for id: TerminalID) {
        guard let session = session(for: id) else { return }
        session.setSurfaceState(visible ? .foreground : .background, isFocused: focusedID == id)
        if visible { session.requestRepaint() }
    }

    public func setWindowFocused(_ focused: Bool) {
        sessions.forEach { $0.setWindowFocused(focused) }
    }

    public func events() -> AsyncStream<TerminalEvent> {
        broadcaster.stream()
    }

    /// Kapanış simetrisi: tek global event monitörünü bırakır. Idempotent'tir.
    /// (Faz 3'te `StoreLifecycle` ile composition root'a bağlanacak.)
    public func shutdown() {
        Self.logger.log("shutdown: event monitor stopped (sessions \(self.sessions.count))")
        eventMonitor.stop()
    }

    // MARK: - Remote mirror

    public func subscribeOutput(_ id: TerminalID) -> AsyncStream<Data> {
        guard let s = session(for: id) else { return AsyncStream { $0.finish() } }
        return s.subscribeRemoteOutput()
    }

    public func writeInput(_ data: Data, to id: TerminalID) {
        session(for: id)?.writeRemoteInput(data)
    }

    public func serializeScrollback(_ id: TerminalID) -> (data: Data, cols: Int, rows: Int) {
        guard let s = session(for: id) else { return (Data(), 0, 0) }
        return s.serializeScrollback()
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

    func session(_ session: TerminalSession, didChangeProvider provider: AgentProvider?) {
        guard isRegistered(session) else { return }
        broadcaster.send(.providerChanged(session.id, provider))
    }

    func session(_ session: TerminalSession, didChangeCodexSessionID sessionID: String) {
        guard isRegistered(session) else { return }
        broadcaster.send(.codexSessionIDChanged(session.id, sessionID))
    }

    func session(_ session: TerminalSession, didChangeStalled stalled: Bool) {
        guard isRegistered(session) else { return }
        broadcaster.send(.stalled(session.id, stalled))
    }

    func session(_ session: TerminalSession, didFailWriteWithErrno code: Int32) {
        guard isRegistered(session) else { return }
        broadcaster.send(.writeFailed(session.id, errno: code))
    }

    func sessionDidBell(_ session: TerminalSession) {
        guard isRegistered(session) else { return }
        broadcaster.send(.bell(session.id))
    }

    /// Karar 57: link tıklaması diğer terminal sinyalleriyle aynı kanaldan akar.
    func session(_ session: TerminalSession, didActivateLink activation: TerminalLinkActivation) {
        guard isRegistered(session) else { return }
        broadcaster.send(.linkActivated(activation))
    }

    func session(_ session: TerminalSession, didExitWithCode code: Int32) {
        // Exit-cleanup sırası: önce kayıttan düş — stale push imkânsızlaşır —
        // sonra exit yayınla
        sessions.removeAll { $0.id == session.id }
        Self.logger.log(
            "exit \(LumiLog.short(session.id), privacy: .public) code \(code) remaining \(self.sessions.count)"
        )
        if focusedID == session.id { focusedID = nil }
        viewRegistry.unregister(session.id)
        broadcaster.send(.exited(session.id, code: code))
    }

    private func isRegistered(_ session: TerminalSession) -> Bool {
        sessions.contains { $0 === session }
    }
}
