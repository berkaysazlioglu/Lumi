import Foundation
import LumiKit

/// Terminal başına okuma/yazma boru hattı durumu (design/01 §3-4).
///
/// TÜM üyelere yalnız terminalin serial io queue'sundan dokunulur; `@unchecked
/// Sendable` bu confinement sözleşmesine dayanır. Callback'ler io queue'da çağrılır;
/// tüketici (TerminalSession) main'e kendisi sıçrar.
final class TerminalPipeline: @unchecked Sendable {
    let flow: FlowController
    let statusMachine = StatusStateMachine()

    private var decoder = UTF8StreamDecoder()
    private let oscParser = OSCStreamParser()
    private var inferencer = ProviderInferencer()
    private var inputFilter = PTYInputFilter()
    private let coalescer: OutputCoalescer
    private let silenceTimer: CodexSilenceTimer

    // @Sendable: bu callback'ler io queue'da çağrılır; MainActor bağlamında atanan
    // closure'ların izolasyon miras almasını engeller (tüketici main'e kendisi sıçrar)
    var onStatusChange: (@Sendable (TerminalStatus) -> Void)?
    var onDisplayTitle: (@Sendable (String) -> Void)?
    var onFlushBatch: (@Sendable (Data) -> Void)?
    var onOutputText: (@Sendable (String) -> Void)?

    init(queue: DispatchQueue, flow: FlowController = FlowController()) {
        self.flow = flow
        self.coalescer = OutputCoalescer(scheduler: DispatchOneShotScheduler(queue: queue))
        self.silenceTimer = CodexSilenceTimer(scheduler: DispatchOneShotScheduler(queue: queue))

        coalescer.onFlush = { [weak self] data in
            self?.onFlushBatch?(data)
        }
        silenceTimer.onSilence = { [weak self] in
            self?.statusMachine.onOutputSilence()
        }
        statusMachine.onChange = { [weak self] status in
            self?.onStatusChange?(status)
        }
    }

    // MARK: - Okuma yolu (spec/10 §3 chunk sırası)

    func processOutput(_ data: Data) -> PTYProcess.ReadDirective {
        let directive = flow.noteProduced(data.count)
        let text = decoder.decode(data)
        if !text.isEmpty {
            inferencer.observeOutput(text)
            var sawTurnComplete = false
            for event in oscParser.feed(text) {
                handle(event, sawTurnComplete: &sawTurnComplete)
            }
            // Codex fallback: turn-complete görülen chunk'ta timer resetlenmez ve
            // aktivite işlenmez — aksi halde "bitti" sinyali anında geri alınırdı
            if inferencer.hint == .codex, !sawTurnComplete {
                statusMachine.onOutputActivity()
                silenceTimer.touch()
            }
            onOutputText?(text)
        }
        coalescer.ingest(data)
        return directive == .suspend ? .suspend : .proceed
    }

    private func handle(_ event: OSCEvent, sawTurnComplete: inout Bool) {
        switch event {
        case .title(let title):
            if let hint = title.providerHint {
                applyHint(hint)
            }
            if let display = title.displayTitle {
                onDisplayTitle?(display)
            }
            if let isWorking = title.isWorking {
                statusMachine.onTitleChange(isWorking: isWorking)
            }
        case .notification(let kind):
            guard kind == .codexTurnComplete else { return }
            sawTurnComplete = true
            applyHint(.codex)
            silenceTimer.cancel()
            statusMachine.onTitleChange(isWorking: false)
        }
    }

    /// Hint claude'a dönerse codex silence timer'ı iptal edilir (spec/10 §4):
    /// Claude tamamen title-tabanlıdır, timer'a gerek yoktur.
    private func applyHint(_ hint: AgentHint) {
        inferencer.applyOSCHint(hint)
        if inferencer.hint == .claude {
            silenceTimer.cancel()
        }
    }

    // MARK: - Yazma yolu (spec/10 §7)

    /// Filtre → inference → \r etkisi. Dönen veri PTY'ye yazılacak veridir;
    /// boşsa yazım atlanır (filtre her şeyi söktüyse).
    func processInput(_ data: Data) -> Data {
        InputTracer.trace("write/pre-filter", data)
        let filtered = inputFilter.filter(data)
        InputTracer.trace("write/post-filter", filtered)
        guard !filtered.isEmpty else { return filtered }
        let text = String(decoding: filtered, as: UTF8.self)
        inferencer.observeInput(text)
        if text.contains("\r"), inferencer.hint == .codex {
            statusMachine.onUserInput()
        }
        return filtered
    }

    // MARK: - Odak / görünürlük / yaşam döngüsü

    func setTabFocused(_ focused: Bool) {
        focused ? statusMachine.onFocus() : statusMachine.onBlur()
    }

    func setWindowFocused(_ focused: Bool) {
        focused ? statusMachine.onWindowFocus() : statusMachine.onWindowBlur()
    }

    func setHidden(_ hidden: Bool) {
        coalescer.setHidden(hidden)
    }

    /// Exit-cleanup'ın io tarafı (spec/10 §9 sırası): timer iptali + kalan
    /// buffer'ın boşaltılması. Status yayını yapılmaz — Electron paritesi:
    /// kayıttan düşmüş terminale stale status push edilmez.
    func prepareForExit() {
        silenceTimer.cancel()
        coalescer.flushNow()
    }

    var currentHint: AgentHint {
        inferencer.hint
    }
}
