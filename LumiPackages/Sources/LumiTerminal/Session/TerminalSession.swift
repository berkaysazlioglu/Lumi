import AppKit
import Foundation
import LumiKit
import SwiftTerm

@MainActor
protocol TerminalSessionDelegate: AnyObject {
    func session(_ session: TerminalSession, didChangeStatus status: TerminalStatus)
    func session(_ session: TerminalSession, didChangeAwaitingDecision awaiting: Bool)
    func session(_ session: TerminalSession, didChangeTitle title: String)
    func session(_ session: TerminalSession, didChangeStalled stalled: Bool)
    func session(_ session: TerminalSession, didExitWithCode code: Int32)
    func session(_ session: TerminalSession, didFailWriteWithErrno code: Int32)
    func sessionDidBell(_ session: TerminalSession)
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
            claudeSessionID: claudeSessionID
        )

        let queue = DispatchQueue(label: "lumi.terminal.\(id.raw.uuidString)", qos: .utility)
        self.ioQueue = queue
        self.pipeline = pipeline ?? TerminalPipeline(queue: queue)

        self.pty = try ptySpawner.spawn(
            executable: ShellResolver.defaultShell(),
            args: ["-l"],
            cwd: repoPath,
            env: TerminalEnvironment.childEnvironment(),
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
        pipeline.onStallChange = { [weak self] stalled in
            hopToMain { self?.applyStalled(stalled) }
        }
    }

    private func wirePTY() {
        pty.onExit = { [weak self, pipeline] code in
            // io queue: önce timer iptal + kalan buffer flush,
            // sonra main'e exit bildirimi — main FIFO teslim sırasını korur
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

    private func applyStalled(_ stalled: Bool) {
        guard !isTerminated else { return }
        delegate?.session(self, didChangeStalled: stalled)
    }

    private func handleExit(code: Int32) {
        guard !isTerminated else { return }
        isTerminated = true
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

    /// Tüm PTY-bound yazımların tek hunisi (design/01 §4): klavye, SwiftTerm
    /// oto-yanıtları, programatik write — hepsi filtre + serial io queue'dan geçer.
    func write(_ data: Data) {
        guard !isTerminated else { return }
        ioQueue.async { [pipeline, pty] in
            let filtered = pipeline.processInput(data)
            guard !filtered.isEmpty else { return }
            pty.write(filtered)
        }
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

    func terminate() {
        pty.terminate()
    }

    /// SIGWINCH poke'u (görsel uzantıdan çağrılır; PTY erişimi burada kapalı kalır).
    func pokePTYRepaint() {
        pty.pokeRepaint()
    }
}
