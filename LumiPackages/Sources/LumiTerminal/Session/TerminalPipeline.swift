import Foundation
import LumiKit

/// Terminal başına okuma/yazma boru hattı durumu (design/01 §3-4).
///
/// TÜM üyelere yalnız terminalin serial io queue'sundan dokunulur; `@unchecked
/// Sendable` bu confinement sözleşmesine dayanır. Callback'ler io queue'da çağrılır;
/// tüketici (TerminalSession) main'e kendisi sıçrar.
///
/// Durum otoritesi (karar 45): ajan hook olayları (`processHookEvent`) geldiği
/// andan itibaren `hookReducer.isBound` açılır ve OSC başlığı / Codex çıktı
/// sessizliği / Enter sezgileri durumu SÜRMEZ — yalnız başlık metnini günceller.
/// Hook yoksa (düz shell, hook kurulamamış) eski sezgisel yol aynen çalışır.
final class TerminalPipeline: @unchecked Sendable {
    let flow: FlowController
    let statusMachine = StatusStateMachine()
    let decisionTracker = DecisionTracker()
    let hookReducer = AgentHookStatusReducer()

    private var decoder = UTF8StreamDecoder()
    private let oscParser = OSCStreamParser()
    /// Ham OSC olaylarını Lumi semantiğine çeviren zincir (Faz 4.8 / OCP):
    /// yeni ajan ya da yeni OSC kodu, pipeline'a dokunmadan enjekte edilir.
    private let semantics: OSCSemanticsChain
    private var inferencer = ProviderInferencer()
    private var inputFilter = PTYInputFilter()
    private let coalescer: OutputCoalescer
    private let silenceTimer: CodexSilenceTimer
    /// Esc/Ctrl+C sonrası hook gelmezse kesme çıkarımı (Orca
    /// `AGENT_INTERRUPT_SETTLE_MS`).
    private let interruptTimer: InterruptSettleTimer
    /// Donma gözetimi + adaptif batching (design/00 Ek A §A.2-10).
    let watchdog: FeedWatchdog
    /// Dışa en son bildirilen sağlayıcı kimliği — yalnız gerçek değişim yayılır.
    private var reportedProvider: AgentProvider?

    // @Sendable: bu callback'ler io queue'da çağrılır; MainActor bağlamında atanan
    // closure'ların izolasyon miras almasını engeller (tüketici main'e kendisi sıçrar)
    var onStatusChange: (@Sendable (TerminalStatus) -> Void)?
    /// "Karar bekliyor" (izin promptu) sinyali — status'ten ayrı; kuyruk tüketir.
    var onAwaitingDecisionChange: (@Sendable (Bool) -> Void)?
    var onDisplayTitle: (@Sendable (String) -> Void)?
    /// Terminaldeki ajan kimliği değişti (karar 45): launch komutu / çıktı
    /// çıkarımı / hook sağlayıcısı; `nil` = düz shell.
    var onProviderChange: (@Sendable (AgentProvider?) -> Void)?
    var onFlushBatch: (@Sendable (Data) -> Void)?
    /// Feed akışı durdu / düzeldi (Ek A §A.2-10). UI "stalled" rozeti gösterir.
    var onStallChange: (@Sendable (Bool) -> Void)?

    /// Scheduler'lar enjekte edilebilir (varsayılan = io queue üzerinde gerçek
    /// dispatch timer'ı): orkestrasyon testleri 16 ms / 3 sn beklemeden,
    /// deterministik olarak koşar (design/01 §7 "öncelikli test hedefleri").
    init(
        queue: DispatchQueue,
        flow: FlowController = FlowController(),
        coalescerScheduler: OneShotScheduling? = nil,
        silenceScheduler: OneShotScheduling? = nil,
        interruptScheduler: OneShotScheduling? = nil,
        semantics: [any OSCSemantics] = OSCSemanticsDefaults.all,
        watchdogHeartbeat: (any HeartbeatScheduling)? = nil,
        clock: any MonotonicClock = SystemMonotonicClock(),
        initialProvider: AgentProvider? = nil
    ) {
        self.flow = flow
        self.semantics = OSCSemanticsChain(semantics)
        self.reportedProvider = initialProvider
        let coalescer = OutputCoalescer(
            scheduler: coalescerScheduler ?? DispatchOneShotScheduler(queue: queue)
        )
        self.coalescer = coalescer
        self.silenceTimer = CodexSilenceTimer(
            scheduler: silenceScheduler ?? DispatchOneShotScheduler(queue: queue)
        )
        self.interruptTimer = InterruptSettleTimer(
            scheduler: interruptScheduler ?? DispatchOneShotScheduler(queue: queue)
        )
        self.watchdog = FeedWatchdog(
            clock: clock,
            heartbeat: watchdogHeartbeat ?? DispatchHeartbeatScheduler(queue: queue),
            budget: coalescer.budget,
            inFlight: { [flow] in flow.inFlight }
        )
        if let initialProvider {
            inferencer.applyOSCHint(AgentHint(rawValue: initialProvider.rawValue))
        }

        coalescer.onFlush = { [weak self] data in
            self?.onFlushBatch?(data)
        }
        silenceTimer.onSilence = { [weak self] in
            self?.statusMachine.onOutputSilence()
        }
        interruptTimer.onSettle = { [weak self] in
            self?.settleInterrupt()
        }
        statusMachine.onChange = { [weak self] status in
            self?.onStatusChange?(status)
        }
        decisionTracker.onChange = { [weak self] awaiting in
            self?.onAwaitingDecisionChange?(awaiting)
        }
        watchdog.onStallChange = { [weak self] stalled in
            self?.onStallChange?(stalled)
        }
        watchdog.start()
    }

    // MARK: - Okuma yolu (chunk sırası)

    func processOutput(_ data: Data) -> PTYProcess.ReadDirective {
        let directive = flow.noteProduced(data.count)
        let text = decoder.decode(data)
        if !text.isEmpty {
            inferencer.observeOutput(text)
            var sawTurnComplete = false
            for raw in oscParser.feed(text) {
                let events = semantics.interpret(raw, hint: inferencer.hint)
                OSCTracer.trace(raw: raw, events: events)
                for event in events {
                    handle(event, sawTurnComplete: &sawTurnComplete)
                }
            }
            // Codex fallback: turn-complete görülen chunk'ta timer resetlenmez ve
            // aktivite işlenmez — aksi halde "bitti" sinyali anında geri alınırdı.
            // Hook otoritesi varken sezgi tamamen susar.
            if inferencer.hint == .codex, !sawTurnComplete, !hookReducer.isBound {
                statusMachine.onOutputActivity()
                silenceTimer.touch()
            }
            reportProviderIfChanged()
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
            guard !hookReducer.isBound, let isWorking = title.isWorking else { return }
            statusMachine.onTitleChange(isWorking: isWorking)
            // Çalışmaya dönüş izin promptunun kapandığını gösterir.
            if isWorking { decisionTracker.onWorking() }
        case .notification(let kind):
            switch kind {
            case .codexTurnComplete:
                sawTurnComplete = true
                applyHint(.codex)
                silenceTimer.cancel()
                guard !hookReducer.isBound else { return }
                statusMachine.onTitleChange(isWorking: false)
            case .permissionRequest:
                // "Karar bekliyor" — status'e dokunma; yalnız ayrı sinyali kaldır.
                guard !hookReducer.isBound else { return }
                decisionTracker.onPermissionRequest()
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

    // MARK: - Hook yolu (karar 45)

    /// Ajan hook olayı: reducer etkilerini durum makinesine uygular. Bekleyen
    /// kesme çıkarımı iptal olur — gerçek sinyal geldi.
    func processHookEvent(_ event: AgentHookEvent) {
        interruptTimer.cancel()
        silenceTimer.cancel()
        let effects = hookReducer.reduce(event)
        apply(effects)
        if case .sessionEnd = event.kind {
            // Ajan çıktı: geride düz shell var; eski çıkarım hint'i de düşer.
            inferencer.reset()
        } else {
            inferencer.applyOSCHint(AgentHint(rawValue: event.provider.rawValue))
        }
        reportProviderIfChanged()
    }

    private func apply(_ effects: [AgentHookEffect]) {
        for effect in effects {
            switch effect {
            case .working:
                statusMachine.onTitleChange(isWorking: true)
            case .turnEnded:
                statusMachine.onTitleChange(isWorking: false)
            case .sessionIdle, .sessionEnded:
                statusMachine.reset()
                decisionTracker.reset()
            case .decisionRequested:
                decisionTracker.onPermissionRequest()
            case .decisionResolved:
                decisionTracker.onWorking()
            }
        }
    }

    /// Esc/Ctrl+C sonrası pencere doldu ve hook gelmedi → kesildi say.
    private func settleInterrupt() {
        guard statusMachine.status == .working else { return }
        apply(hookReducer.inferInterrupt())
    }

    private func reportProviderIfChanged() {
        let current: AgentProvider? = hookReducer.isBound
            ? hookReducer.provider
            : AgentProvider(rawValue: inferencer.hint.rawValue)
        guard current != reportedProvider else { return }
        reportedProvider = current
        onProviderChange?(current)
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
        if hookReducer.isBound {
            if statusMachine.status == .working, InterruptSettleTimer.isInterruptKeystroke(filtered) {
                interruptTimer.touch()
            }
        } else if text.contains("\r"), inferencer.hint == .codex {
            statusMachine.onUserInput()
        }
        reportProviderIfChanged()
        return filtered
    }

    // MARK: - Odak / yüzey / yaşam döngüsü

    func setTabFocused(_ focused: Bool) {
        focused ? statusMachine.onFocus() : statusMachine.onBlur()
    }

    func setWindowFocused(_ focused: Bool) {
        focused ? statusMachine.onWindowFocus() : statusMachine.onWindowBlur()
    }

    /// Faz 4.3 — yüzey geçişinin io tarafı: akış politikası (coalescer aralığı)
    /// ve odak (status makinesi) TEK çağrıda, aynı serial queue adımında
    /// uygulanır. İkisi ayrı çağrılardan aksaydı aradaki pencerede "görünmüyor
    /// ama hâlâ odaklı" ara durumu gözlemlenebilirdi.
    ///
    /// `isFocused` otoritesi manager'dadır (`setFocused`): foreground olmak
    /// tek başına odak kazandırmaz — grid'deki her kart foreground'dur, yalnız
    /// biri odaklıdır.
    func applySurfaceState(_ state: TerminalSurfaceState, isFocused: Bool) {
        coalescer.setHidden(!state.isVisible)
        if state.isVisible {
            if isFocused { statusMachine.onFocus() }
        } else {
            statusMachine.onBlur()
        }
    }

    /// Exit-cleanup'ın io tarafı (sıra-bağımlı): timer iptali + kalan
    /// buffer'ın boşaltılması. Status yayını yapılmaz — Electron paritesi:
    /// kayıttan düşmüş terminale stale status push edilmez.
    func prepareForExit() {
        watchdog.stop()
        silenceTimer.cancel()
        interruptTimer.cancel()
        decisionTracker.reset()
        coalescer.flushNow()
    }

    /// Exit-cleanup'ın sıra-bağımlı ikinci yarısı (design/01 §6): timer iptal →
    /// OSC buffer sil → status makinesine exit. Terminal kayıttan düştükten SONRA
    /// çağrılır; buradan doğan status yayını tüketici tarafında (isTerminated)
    /// süzülür — bayat push Electron paritesinde de yoktur.
    func finishExit(code: Int32) {
        watchdog.stop()
        silenceTimer.cancel()
        interruptTimer.cancel()
        oscParser.reset()
        hookReducer.reset()
        statusMachine.onExit(code: code)
    }

    var currentHint: AgentHint {
        inferencer.hint
    }
}
