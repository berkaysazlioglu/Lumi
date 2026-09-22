import AppKit
import Foundation
import LumiKit
import SwiftTerm
import os

/// Teşhis izi (karar 83); io queue'dan da yazılabilsin diye dosya düzeyinde.
private let sessionLogger = LumiLog.logger("terminal")

@MainActor
protocol TerminalSessionDelegate: AnyObject {
    func session(_ session: TerminalSession, didChangeStatus status: TerminalStatus)
    func session(_ session: TerminalSession, didChangeAwaitingDecision awaiting: Bool)
    func session(_ session: TerminalSession, didChangeTitle title: String)
    func session(_ session: TerminalSession, didChangeProvider provider: AgentProvider?)
    /// Karar 90: doğrulanmış lider Codex hook'undan thread kimliği geldi.
    func session(_ session: TerminalSession, didChangeCodexSessionID sessionID: String)
    func session(_ session: TerminalSession, didChangeStalled stalled: Bool)
    func session(_ session: TerminalSession, didExitWithCode code: Int32)
    func session(_ session: TerminalSession, didFailWriteWithErrno code: Int32)
    func sessionDidBell(_ session: TerminalSession)
    /// Karar 57: terminalde bir link/path tıklandı.
    func session(_ session: TerminalSession, didActivateLink activation: TerminalLinkActivation)
}

/// Bir PTY oturumu + kalıcı SwiftTerm emülatörü (design/01 §1 — Seçenek A).
///
/// View PTY ömrü boyunca yaşar ve asla yok edilmez; ekran durumu yalnız burada,
/// emülatördedir. Replay/snapshot makinesi yoktur. PTY I/O io queue'da,
/// emülatör feed'i MainActor'da akar; ack senkron feed dönüşünde verilir.
///
/// Faz 4.1 sonrası bu tip yalnız **orkestrasyon** yapar: PTY (`PTYSpawning`),
/// view (`TerminalViewMaking`) ve görsel komutlar (`TerminalPresentation`)
/// enjekte edilen işbirlikçilerdir.
@MainActor
final class TerminalSession {
    static let initialCols: UInt16 = 120
    static let initialRows: UInt16 = 30
    static let scrollbackLines = 5000
    static let resizeDebounceInterval: TimeInterval = 0.15

    let id: TerminalID
    private(set) var meta: TerminalMeta
    weak var delegate: TerminalSessionDelegate?

    private let pty: any PTYControlling
    private let ioQueue: DispatchQueue
    private let pipeline: TerminalPipeline
    /// Ham PTY bayt batch'leri için broadcaster (remote mirror).
    private let remoteOutputBroadcaster = EventBroadcaster<Data>()
    let presentation: TerminalPresentation
    /// Exit sonrası her dış etki susar (bell dahil) — bayat sinyal yayılmaz.
    private(set) var isTerminated = false
    /// Son uygulanan yüzey durumu (Faz 4.3). Spawn anında hiçbir container'a
    /// bağlı olmadığından `.background` başlar — registry attach'te öne alır.
    private(set) var surfaceState: TerminalSurfaceState = .background
    private var pendingResize: DispatchWorkItem?
    private var launchGate: LaunchCommandGate?

    init(
        repoPath: String,
        name: String,
        task: String?,
        claudeSessionID: String? = nil,
        codexSessionID: String? = nil,
        codexHome: String? = nil,
        provider: AgentProvider? = nil,
        environment: [String: String] = [:],
        hookEndpoint: AgentHookEndpoint? = nil,
        font: NSFont,
        ptySpawner: any PTYSpawning = SystemPTYSpawner(),
        viewMaker: any TerminalViewMaking = DropAwareTerminalViewMaker(),
        pipeline: TerminalPipeline? = nil
    ) throws {
        let id = TerminalID()
        self.id = id
        self.meta = TerminalMeta(
            id: id,
            name: name,
            repoPath: repoPath,
            createdAt: Date(),
            task: task,
            claudeSessionID: claudeSessionID,
            codexSessionID: codexSessionID,
            codexHome: codexHome,
            provider: provider
        )

        let queue = DispatchQueue(label: "lumi.terminal.\(id.raw.uuidString)", qos: .utility)
        self.ioQueue = queue
        self.pipeline = pipeline ?? TerminalPipeline(queue: queue, initialProvider: provider)

        self.pty = try ptySpawner.spawn(
            executable: ShellResolver.defaultShell(),
            args: ["-l"],
            cwd: repoPath,
            env: TerminalEnvironment.childEnvironment(
                overrides: environment, hookEndpoint: hookEndpoint, terminalID: id
            ),
            cols: Self.initialCols,
            rows: Self.initialRows,
            queue: queue
        )

        let view = viewMaker.makeView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 480),
            font: font
        )
        self.presentation = TerminalPresentation(view: view, scrollbackLines: Self.scrollbackLines)
        view.terminalDelegate = self
        (view as? FileDropAccepting)?.onFileDrop = { [weak self] paths in
            // Quote'lanmış path, newline'sız yazılır (Electron paritesi + karar 11)
            self?.write(ShellQuoting.joinedPaths(paths))
        }
        (view as? DropAwareTerminalView).map { linkView in
            // Karar 57: link jestleri oturuma akar — düz tıkın fare raporu
            // popover'a dönüşürse PTY'ye hiç gitmez.
            linkView.onLinkGestureBegan = { [weak self] in self?.beginDeferringMouseReports() }
            linkView.onLinkGestureEnded = { [weak self] claimed in
                self?.endDeferringMouseReports(claimed: claimed)
            }
            linkView.onLinkActivation = { [weak self] link, gesture, anchor in
                guard let self else { return }
                self.delegate?.session(self, didActivateLink: TerminalLinkActivation(
                    terminalID: id, link: link, gesture: gesture, anchor: anchor
                ))
            }
        }

        wirePipeline()
        wirePTY()
    }

    // MARK: - Kablolama (io → main)

    private func wirePipeline() {
        pipeline.onFlushBatch = { [weak self] data in
            hopToMain { self?.deliver(data) }
        }
        pipeline.onStatusChange = { [weak self] status in
            hopToMain { self?.applyStatus(status) }
        }
        pipeline.onAwaitingDecisionChange = { [weak self] awaiting in
            hopToMain { self?.applyAwaitingDecision(awaiting) }
        }
        pipeline.onDisplayTitle = { [weak self] title in
            hopToMain { self?.applyTitle(title) }
        }
        pipeline.onProviderChange = { [weak self] provider in
            hopToMain { self?.applyProvider(provider) }
        }
        pipeline.onStallChange = { [weak self] stalled in
            hopToMain { self?.applyStalled(stalled) }
        }
    }

    private func wirePTY() {
        let sessionID = id
        pty.onExit = { [weak self, pipeline] code in
            // io queue: önce timer iptal + kalan buffer flush,
            // sonra main'e exit bildirimi — main FIFO teslim sırasını korur
            sessionLogger.log("pty exit \(LumiLog.short(sessionID), privacy: .public) code \(code) (io queue)")
            pipeline.prepareForExit()
            hopToMain { self?.handleExit(code: code) }
        }
        pty.onWriteFailure = { [weak self] code in
            hopToMain { self?.handleWriteFailure(code) }
        }
        pty.startReading { [pipeline] data in
            pipeline.processOutput(data)
        }
    }

    /// Ack noktası: SwiftTerm feed'i senkron parse eder; dönüş = tüketildi
    /// (design/00 Ek A §A.1-2). Ölü oturuma teslim sessizce atlanır (native safeSend) —
    /// PTY suspend'de kalır, veri kaybolmaz. Feed süresi watchdog'a ölçtürülür
    /// (Ek A §A.2-10: >4 ms bütçe aşımı flush eşiğini küçültür).
    private func deliver(_ batch: Data) {
        guard !isTerminated else { return }
        launchGate?.noteOutput()
        pipeline.watchdog.measureFeed { presentation.feed(batch) }
        remoteOutputBroadcaster.send(batch)
        if pipeline.flow.noteConsumed(batch.count) {
            pty.resumeReading()
        }
    }

    private func applyStatus(_ status: TerminalStatus) {
        guard !isTerminated else { return }
        meta.status = status
        delegate?.session(self, didChangeStatus: status)
    }

    private func applyAwaitingDecision(_ awaiting: Bool) {
        guard !isTerminated else { return }
        delegate?.session(self, didChangeAwaitingDecision: awaiting)
    }

    private func applyTitle(_ title: String) {
        guard !isTerminated else { return }
        meta.oscTitle = title
        delegate?.session(self, didChangeTitle: title)
    }

    private func applyProvider(_ provider: AgentProvider?) {
        guard !isTerminated, meta.provider != provider else { return }
        meta.provider = provider
        delegate?.session(self, didChangeProvider: provider)
    }

    private func applyStalled(_ stalled: Bool) {
        guard !isTerminated else { return }
        delegate?.session(self, didChangeStalled: stalled)
    }

    private func handleExit(code: Int32) {
        guard !isTerminated else { return }
        isTerminated = true
        sessionLogger.log("handleExit \(LumiLog.short(self.id), privacy: .public) code \(code) delegate=\(self.delegate != nil)")
        pendingResize?.cancel()
        launchGate?.cancel()
        launchGate = nil
        // design/01 §6 sırası: terminal kayıttan düştükten (isTerminated) sonra,
        // exit yayınından önce io tarafı kapanışı — timer iptal → OSC buffer sil →
        // statusMachine.onExit. Buradan doğan status yayını applyStatus'ta süzülür.
        ioQueue.async { [pipeline] in
            pipeline.finishExit(code: code)
        }
        delegate?.session(self, didExitWithCode: code)
    }

    /// PTY yazımı kalıcı olarak başarısız (child öldü) — karar 5: sessizce yutulmaz.
    private func handleWriteFailure(_ code: Int32) {
        guard !isTerminated else { return }
        delegate?.session(self, didFailWriteWithErrno: code)
    }

    // MARK: - Komutlar

    /// Launch komutunu shell hazır olunca yazar (karar 23): erken PTY yazımı
    /// shell init'inin girdi-flush'una denk gelip kaybolabiliyor — bkz.
    /// `LaunchCommandGate`.
    func scheduleLaunchCommand(_ command: String) {
        let gate = LaunchCommandGate()
        launchGate = gate
        gate.start { [weak self] in
            self?.write(command + "\r")
            self?.launchGate = nil
        }
    }

    func write(_ text: String) {
        write(Data(text.utf8))
    }

    /// Karar 45: hook sunucusundan gelen olay, diğer tüm durum sinyalleriyle
    /// aynı serial io queue'da uygulanır — OSC ve hook birbirini yarıştırmaz.
    func applyHookEvent(_ event: AgentHookEvent) {
        guard !isTerminated else { return }
        ioQueue.async { [weak self, pipeline] in
            pipeline.processHookEvent(event)
            guard event.provider == .codex, event.isLead,
                  let sessionID = event.sessionID else { return }
            hopToMain { self?.applyCodexSessionID(sessionID) }
        }
    }

    private func applyCodexSessionID(_ sessionID: String) {
        guard !isTerminated, meta.codexSessionID != sessionID else { return }
        meta.codexSessionID = sessionID
        delegate?.session(self, didChangeCodexSessionID: sessionID)
    }

    // MARK: - Remote mirror

    func subscribeRemoteOutput() -> AsyncStream<Data> {
        remoteOutputBroadcaster.stream()
    }

    func writeRemoteInput(_ data: Data) {
        write(data)
    }

    func serializeScrollback() -> (data: Data, cols: Int, rows: Int) {
        // getBufferAsData() SwiftTerm'in public API'si (Terminal.swift:5919):
        // active buffer'ın TÜM satırlarını (scrollback + visible) UTF-8 döker —
        // telefon subscribe'da tam geçmişi görür. Sadece görünür satırlar YETMEZ.
        let terminal = presentation.view.getTerminal()
        let dims = terminal.getDims()
        return (data: terminal.getBufferAsData(), cols: dims.cols, rows: dims.rows)
    }

    /// Karar 57: düz tıkla açılan link eylemleri (Settings ▸ Terminal).
    func setLinkActionsEnabled(_ enabled: Bool) {
        (terminalView as? DropAwareTerminalView)?.isLinkActionsEnabled = enabled
    }

    // MARK: - Test yardımcıları (LumiTerminalTests)

    @MainActor
    static func makeForTest() throws -> TerminalSession {
        try TerminalSession(
            repoPath: NSTemporaryDirectory(),
            name: "test",
            task: nil,
            font: .monospacedSystemFont(ofSize: 13, weight: .regular)
        )
    }

    func injectFlushBatch(_ data: Data) {
        deliver(data)
    }

    /// Tüm PTY-bound yazımların tek hunisi (design/01 §4): klavye, SwiftTerm
    /// oto-yanıtları, programatik write — hepsi filtre + serial io queue'dan geçer.
    func write(_ data: Data) {
        guard !isTerminated else { return }
        if deferMouseReportIfNeeded(data) { return }
        ioQueue.async { [pipeline, pty] in
            let filtered = pipeline.processInput(data)
            guard !filtered.isEmpty else { return }
            pty.write(filtered)
        }
    }

    // MARK: - Link jesti sırasında fare raporlarını bekletme (karar 57)

    /// Bekleyen fare raporları; `nil` = bekletme kapalı. Düz tık bir linkin
    /// üstünde başladığında açılır: tık popover'a dönüşürse raporlar düşürülür
    /// (Claude caret'i oynamaz), dönüşmezse olduğu gibi akar.
    private var deferredMouseReports: [Data]?
    /// Emniyet tavanı: beklenmedik bir olay seli bekletmeyi kilitlemesin.
    private static let maxDeferredMouseReports = 64

    private func beginDeferringMouseReports() {
        deferredMouseReports = []
    }

    private func endDeferringMouseReports(claimed: Bool) {
        let pending = deferredMouseReports
        deferredMouseReports = nil
        guard !claimed, let pending else { return }
        pending.forEach { write($0) }
    }

    /// `true` → rapor bekletildi, bu çağrıda PTY'ye yazılmaz.
    private func deferMouseReportIfNeeded(_ data: Data) -> Bool {
        guard var pending = deferredMouseReports, TerminalMouseReport.isReport(data) else { return false }
        guard pending.count < Self.maxDeferredMouseReports else {
            endDeferringMouseReports(claimed: false)
            return false
        }
        pending.append(data)
        deferredMouseReports = pending
        return true
    }

    func requestResize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0, !isTerminated else { return }
        pendingResize?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isTerminated else { return }
            self.ioQueue.async { [pty = self.pty] in
                pty.resize(cols: UInt16(cols), rows: UInt16(rows))
            }
        }
        pendingResize = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.resizeDebounceInterval, execute: work)
    }

    func setTabFocused(_ focused: Bool) {
        ioQueue.async { [pipeline] in
            pipeline.setTabFocused(focused)
        }
    }

    func setWindowFocused(_ focused: Bool) {
        ioQueue.async { [pipeline] in
            pipeline.setWindowFocused(focused)
        }
    }

    /// Faz 4.3 — yüzey geçişi: görünürlük politikası ve odak TEK atomik adımda
    /// (io queue'da) uygulanır. `isFocused` çağıranın (manager) bildiği odak
    /// otoritesidir; oturum kendi başına odak varsaymaz.
    func setSurfaceState(_ state: TerminalSurfaceState, isFocused: Bool) {
        guard !isTerminated else { return }
        surfaceState = state
        ioQueue.async { [pipeline] in
            pipeline.applySurfaceState(state, isFocused: isFocused)
        }
    }

    /// PTY çocuk sürecinin pid'i; sonlanmış oturumda `nil`.
    var processID: Int32? { isTerminated ? nil : pty.processID }

    func terminate() {
        sessionLogger.log("terminate \(LumiLog.short(self.id), privacy: .public) pid \(self.pty.processID.map(String.init) ?? "nil", privacy: .public)")
        pty.terminate()
    }

    /// SIGWINCH poke'u (görsel uzantıdan çağrılır; PTY erişimi burada kapalı kalır).
    func pokePTYRepaint() {
        pty.pokeRepaint()
    }
}
