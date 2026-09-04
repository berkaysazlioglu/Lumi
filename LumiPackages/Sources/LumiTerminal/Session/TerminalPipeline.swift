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
    let decisionTracker = DecisionTracker()

    private var decoder = UTF8StreamDecoder()
    private let oscParser = OSCStreamParser()
    private var inferencer = ProviderInferencer()
    private var inputFilter = PTYInputFilter()
    private let coalescer: OutputCoalescer
    private let silenceTimer: CodexSilenceTimer

    // @Sendable: bu callback'ler io queue'da çağrılır; MainActor bağlamında atanan
    // closure'ların izolasyon miras almasını engeller (tüketici main'e kendisi sıçrar)
    var onStatusChange: (@Sendable (TerminalStatus) -> Void)?
    /// "Karar bekliyor" (izin promptu) sinyali — status'ten ayrı; kuyruk tüketir.
    var onAwaitingDecisionChange: (@Sendable (Bool) -> Void)?
    var onDisplayTitle: (@Sendable (String) -> Void)?
    var onFlushBatch: (@Sendable (Data) -> Void)?

    /// Scheduler'lar enjekte edilebilir (varsayılan = io queue üzerinde gerçek
    /// dispatch timer'ı): orkestrasyon testleri 16 ms / 3 sn beklemeden,
    /// deterministik olarak koşar (design/01 §7 "öncelikli test hedefleri").
    init(
        queue: DispatchQueue,
        flow: FlowController = FlowController(),
        coalescerScheduler: OneShotScheduling? = nil,
        silenceScheduler: OneShotScheduling? = nil
    ) {
        self.flow = flow
        self.coalescer = OutputCoalescer(
            scheduler: coalescerScheduler ?? DispatchOneShotScheduler(queue: queue)
        )
        self.silenceTimer = CodexSilenceTimer(
            scheduler: silenceScheduler ?? DispatchOneShotScheduler(queue: queue)
        )

        coalescer.onFlush = { [weak self] data in
            self?.onFlushBatch?(data)
        }
        silenceTimer.onSilence = { [weak self] in
            self?.statusMachine.onOutputSilence()
        }
        statusMachine.onChange = { [weak self] status in
            self?.onStatusChange?(status)
        }
        decisionTracker.onChange = { [weak self] awaiting in
            self?.onAwaitingDecisionChange?(awaiting)
        }
    }

    // MARK: - Okuma yolu (chunk sırası)

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
                // Çalışmaya dönüş izin promptunun kapandığını gösterir.
                if isWorking { decisionTracker.onWorking() }
            }
        case .notification(let kind):
            switch kind {
            case .codexTurnComplete:
                sawTurnComplete = true
                applyHint(.codex)
                silenceTimer.cancel()
                statusMachine.onTitleChange(isWorking: false)
            case .permissionRequest:
                // "Karar bekliyor" — status'e dokunma; yalnız ayrı sinyali kaldır.
                decisionTracker.onPermissionRequest()
            case .generic:
                break
            }
        }
    }

    /// Hint claude'a dönerse codex silence timer'ı iptal edilir:
    /// Claude tamamen title-tabanlıdır, timer'a gerek yoktur.
    private func applyHint(_ hint: AgentHint) {
        inferencer.applyOSCHint(hint)
        if inferencer.hint == .claude {
            silenceTimer.cancel()
        }
    }

    // MARK: - Yazma yolu

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

    /// Exit-cleanup'ın io tarafı (sıra-bağımlı): timer iptali + kalan
    /// buffer'ın boşaltılması. Status yayını yapılmaz — Electron paritesi:
    /// kayıttan düşmüş terminale stale status push edilmez.
    func prepareForExit() {
        silenceTimer.cancel()
        decisionTracker.reset()
        coalescer.flushNow()
    }

    /// Exit-cleanup'ın sıra-bağımlı ikinci yarısı (design/01 §6): timer iptal →
    /// OSC buffer sil → status makinesine exit. Terminal kayıttan düştükten SONRA
    /// çağrılır; buradan doğan status yayını tüketici tarafında (isTerminated)
    /// süzülür — bayat push Electron paritesinde de yoktur.
    func finishExit(code: Int32) {
        silenceTimer.cancel()
        oscParser.reset()
        statusMachine.onExit(code: code)
    }

    var currentHint: AgentHint {
        inferencer.hint
    }
}
