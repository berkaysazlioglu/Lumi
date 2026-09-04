import AppKit
import Foundation
import LumiKit
import SwiftTerm

@MainActor
protocol TerminalSessionDelegate: AnyObject {
    func session(_ session: TerminalSession, didChangeStatus status: TerminalStatus)
    func session(_ session: TerminalSession, didChangeAwaitingDecision awaiting: Bool)
    func session(_ session: TerminalSession, didChangeTitle title: String)
    func session(_ session: TerminalSession, didExitWithCode code: Int32)
    func session(_ session: TerminalSession, didFailWriteWithErrno code: Int32)
    func sessionDidBell(_ session: TerminalSession)
}

/// Bir PTY oturumu + kalıcı SwiftTerm emülatörü (design/01 §1 — Seçenek A).
///
/// View PTY ömrü boyunca yaşar ve asla yok edilmez; ekran durumu yalnız burada,
/// emülatördedir. Replay/snapshot makinesi yoktur. PTY I/O io queue'da,
/// emülatör feed'i MainActor'da akar; ack senkron feed dönüşünde verilir.
@MainActor
final class TerminalSession {
    static let initialCols: UInt16 = 120
    static let initialRows: UInt16 = 30
    static let scrollbackLines = 5000
    static let resizeDebounceInterval: TimeInterval = 0.15

    let id: TerminalID
    private(set) var meta: TerminalMeta
    let terminalView: TerminalView
    weak var delegate: TerminalSessionDelegate?

    // MARK: - Gözlem noktaları (yalnız test)

    /// PTY'ye FİİLEN yazılan (filtre sonrası) byte'lar; io queue'da çağrılır.
    /// design/00 Ek A §A.2-12 entegrasyon testinin ölçüm noktası: "detach/attach
    /// boyunca PTY'ye sıfır istenmeyen byte". Üretimde hiç set edilmez.
    var onPTYWrite: (@Sendable (Data) -> Void)?

    /// PTY'ye giden ioctl(TIOCSWINSZ) çağrıları; io queue'da çağrılır.
    /// 150 ms resize debounce'unun (design/01 §6) ölçüm noktası.
    var onPTYResize: (@Sendable (UInt16, UInt16) -> Void)?

    private let pty: PTYProcess
    private let ioQueue: DispatchQueue
    private let pipeline: TerminalPipeline
    private var isTerminated = false
    private var pendingResize: DispatchWorkItem?

    init(
        repoPath: String,
        name: String,
        task: String?,
        claudeSessionID: String? = nil,
        font: NSFont,
        executable: String = ShellResolver.defaultShell(),
        args: [String] = ["-l"]
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
        self.pipeline = TerminalPipeline(queue: queue)

        self.pty = try PTYProcess(
            executable: executable,
            args: args,
            cwd: repoPath,
            env: TerminalEnvironment.childEnvironment(),
            initialCols: Self.initialCols,
            initialRows: Self.initialRows,
            queue: queue
        )

        let view = DropAwareTerminalView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 480),
            font: font
        )
        self.terminalView = view
        terminalView.getTerminal().options.scrollback = Self.scrollbackLines
        terminalView.terminalDelegate = self
        view.onFileDrop = { [weak self] paths in
            // Quote'lanmış path, newline'sız yazılır (Electron paritesi + karar 11)
            self?.write(ShellQuoting.joinedPaths(paths))
        }

        wirePipeline()

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

    // MARK: - Pipeline kablolaması (io → main)

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
    }

    /// Ack noktası: SwiftTerm feed'i senkron parse eder; dönüş = tüketildi
    /// (design/00 Ek A §A.1-2). Ölü oturuma teslim sessizce atlanır (native safeSend) —
    /// PTY suspend'de kalır, veri kaybolmaz.
    private func deliver(_ batch: Data) {
        guard !isTerminated else { return }
        launchGate?.noteOutput()
        terminalView.feed(byteArray: ArraySlice([UInt8](batch)))
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

    private var launchGate: LaunchCommandGate?

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
        ioQueue.async { [pipeline, pty, onPTYWrite] in
            let filtered = pipeline.processInput(data)
            guard !filtered.isEmpty else { return }
            onPTYWrite?(filtered)
            pty.write(filtered)
        }
    }

    func requestResize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0, !isTerminated else { return }
        pendingResize?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isTerminated else { return }
            self.ioQueue.async { [pty = self.pty, onPTYResize = self.onPTYResize] in
                onPTYResize?(UInt16(cols), UInt16(rows))
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

    func setHidden(_ hidden: Bool) {
        ioQueue.async { [pipeline] in
            pipeline.setHidden(hidden)
        }
    }

    /// Gizli→görünür geçişi (grid↔maximize round-trip, fullscreen) sonrası TUI'yi
    /// tüm ekranı yeniden çizmeye zorlar. Boyut değişmediğinde hiçbir resize
    /// tetiklenmediğinden emülatör reflow'u ekranda görünmüyor, kart boş kalıyordu
    /// (needsDisplay tek başına yetmiyor — TUI ancak SIGWINCH ile repaint eder).
    /// Asıl onarım: `updateFullScreen` tüm hücreleri dirty işaretler, böylece
    /// reattach sonrası (dirty hücre kalmadığından `needsDisplay` tek başına boş
    /// çizerdi) emülatör buffer'ındaki son kare hem TUI hem düz bash için anında
    /// görünür. Ek olarak SIGWINCH poke'u TUI'nin (Claude Code) iç durumunu da
    /// tazeler. requestRepaint MainActor'da çağrılır.
    func requestRepaint() {
        guard !isTerminated else { return }
        redrawFromBuffer()
        pty.pokeRepaint()
    }

    /// Buffer'dan tam yeniden çizim, SIGWINCH poke'u OLMADAN. Frame-oturma
    /// yolunda (tab değişimi sonrası reassert, pencere resize) kullanılır —
    /// boyut değiştiyse SwiftTerm sizeChanged → PTY resize zinciri SIGWINCH'i
    /// zaten üretir; her layout frame'inde ek poke TUI'yi spam'lerdi.
    func redrawFromBuffer() {
        guard !isTerminated else { return }
        terminalView.getTerminal().updateFullScreen()
        terminalView.setNeedsDisplay(terminalView.bounds)
    }


    /// Caret şekli + blink canlı uygular (Settings → Cursor). SwiftTerm caret'i
    /// otomatik günceller; ek redraw gerekmez.
    func setCursorStyle(_ style: CursorStyle) {
        guard !isTerminated else { return }
        terminalView.getTerminal().setCursorStyle(style)
    }

    /// Font (aile + boyut) canlı uygular. SwiftTerm setter zinciri hücre
    /// boyutlarını yeniden hesaplar, resize'lar (PTY'ye SIGWINCH) ve needsDisplay
    /// işaretler. Ek olarak host'tan yeniden yerleşim istenir: hücre boyutu
    /// değişince ızgaranın kapladığı alan da değişir ve ortalama (TerminalGridFit)
    /// yalnız layout'ta yapılır — istenmezse boşluk bir sonraki resize'a dek
    /// yeniden alta/sağa kayardı.
    func setFont(_ font: NSFont) {
        guard !isTerminated else { return }
        terminalView.font = font
        terminalView.superview?.needsLayout = true
    }

    func terminate() {
        pty.terminate()
    }
}

// MARK: - SwiftTerm delegate köprüsü

/// Delegate çağrıları AppKit'ten (main) gelir; protokol isolasyonsuz olduğundan
/// @preconcurrency conformance runtime'da MainActor'ı doğrular.
extension TerminalSession: @preconcurrency TerminalViewDelegate {
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        requestResize(cols: newCols, rows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        // Bilinçli no-op: title semantiğini Lumi'nin kendi OSC parser'ı sürer (design/01 §6)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        // Klavye + emülatör oto-yanıtları (mode 1004 focus event'leri dahil) —
        // hepsi filtreli yazma hunisinden geçer
        write(Data(data))
    }

    func scrolled(source: TerminalView, position: Double) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        // http/https whitelist paritesi (Electron paritesi)
        guard let url = URL(string: link),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }
        NSWorkspace.shared.open(url)
    }

    func bell(source: TerminalView) {
        guard !isTerminated else { return }
        delegate?.sessionDidBell(self)
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        // OSC 52: Electron sürümünde yoktu; bilinçli no-op (parite)
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
