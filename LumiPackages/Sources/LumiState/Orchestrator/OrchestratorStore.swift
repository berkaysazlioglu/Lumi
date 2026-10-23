import Foundation
import LumiKit
import Observation

/// Orchestrator'ın tek kaynağı (karar 123): kullanıcının doğrudan konuştuğu
/// etkileşimli bir Codex terminali — docked panelde ya da popup'ta (karar 124).
///
/// Terminal, ana terminal servisinden AYRI bir yöneticide yaşar — grid'e,
/// Projects'e, telefona ve resume listesine hiç girmez. Codex yalnız Lumi'nin
/// MCP araçlarıyla çalışır; talimatı her açılışta canlı durumdan üretilir
/// (`OrchestratorPrompt`). Popup'ı kapatmak yalnız gizler; süreç yaşar.
/// Konuşma Codex thread kimliğiyle (`orchestratorCodexThreadID`) sürdürülür.
@Observable
@MainActor
public final class OrchestratorStore {
    public enum Phase: Equatable, Sendable {
        /// Hiç başlamadı (panel ya da popup açılınca başlar).
        case idle
        case starting
        case running
        /// Codex bulunamadı — kurulum paneli.
        case codexMissing
        /// Kurulum script'i orchestrator terminalinde koşuyor.
        case installing
        /// Codex çıktı ya da açılamadı — `Restart` bekler.
        case stopped
    }

    /// Karar 124: orchestrator terminalini çizebilen yüzeyler.
    public enum Host: Hashable, Sendable {
        /// Orta alan ile sağ panel arasındaki docked panel.
        case panel
        /// %80'lik popup.
        case popup
    }

    /// `Install` butonunun koştuğu ve `Copy` ile kopyalanan komut.
    public static let installCommand = "curl -fsSL https://chatgpt.com/codex/install.sh | sh"
    /// Resume'dan hemen sonraki çıkış = thread artık yok; bir kez yeni konuşmaya düşülür.
    static let resumeFailureWindow: Duration = .seconds(15)

    public private(set) var phase: Phase = .idle
    /// Popup'ta gösterilen terminal (Codex ya da kurulum).
    public private(set) var terminalID: TerminalID?
    public private(set) var status: TerminalStatus = .idle
    public private(set) var threadID: String?
    /// Son başarısızlık — panelde satır içi gösterilir.
    public private(set) var errorMessage: String?
    /// Ajanlardan gelen haiku özetleri (Activity paneli).
    public let activity: OrchestratorActivityFeed
    /// Raporu gelen, izlenen terminaller (konuşmaya aittir).
    public let watchList: OrchestratorWatchList
    /// Karar 126: araç çağrılarının ışık süzmeleri (kabuk overlay'i çizer).
    public let flights: OrchestratorFlights
    /// Orchestrator terminalinin view köprüsü (ana registry'den ayrı).
    @ObservationIgnored public let viewProvider: any TerminalViewProviding

    @ObservationIgnored private let terminal: any TerminalSessionControlling
    @ObservationIgnored private let launcher: any OrchestratorLaunching
    @ObservationIgnored private let config: any ConfigServicing
    @ObservationIgnored private let control: (any OrchestratorControlServing)?
    @ObservationIgnored private let tools: (any OrchestratorToolHandling)?
    @ObservationIgnored private let workingDirectory: String
    @ObservationIgnored private let promptContext: @MainActor () -> (projects: String, watched: [String])
    @ObservationIgnored private let codexHome: @Sendable () async -> String?
    @ObservationIgnored private let consumer = EventConsumer(label: "orchestrator")
    /// Bu açılışın bilgisi: resume mı, ne zaman, thread öğrenildi mi?
    @ObservationIgnored private var launch: LaunchRecord?
    /// Bilerek kapatılan terminaller (restart / yeni konuşma / quit) — çıkışları hata değildir.
    @ObservationIgnored private var expectedExits: Set<TerminalID> = []
    @ObservationIgnored private var isLaunching = false
    /// Yeni konuşma açıldı ama Codex thread'ini henüz bildirmedi: diskteki
    /// eski thread bu arada resume edilmesin.
    @ObservationIgnored private var ignoresStoredThread = false
    /// Karar 124: terminali o an çizen yüzeyler.
    @ObservationIgnored private var presentedHosts: Set<Host> = []
    /// Odak istendi ama terminal henüz doğmadı.
    @ObservationIgnored private var focusWhenSpawned = false

    private struct LaunchRecord {
        let resumedThread: String?
        let codexHome: String?
        let at: ContinuousClock.Instant
        var learnedThread = false
    }

    /// Faz 2: Codex thread'ini bildirdi — monitör bekleyen özetleri bıraksın.
    @ObservationIgnored public var onDeliveryTargetAvailable: (@MainActor () -> Void)?

    public init(
        terminal: any TerminalSessionControlling,
        viewProvider: any TerminalViewProviding,
        launcher: any OrchestratorLaunching,
        config: any ConfigServicing,
        workingDirectory: String,
        control: (any OrchestratorControlServing)? = nil,
        tools: (any OrchestratorToolHandling)? = nil,
        activity: OrchestratorActivityFeed = OrchestratorActivityFeed(),
        watchList: OrchestratorWatchList = OrchestratorWatchList(),
        flights: OrchestratorFlights = OrchestratorFlights(),
        promptContext: @escaping @MainActor () -> (projects: String, watched: [String]) = { ("(no projects)", []) },
        codexHome: @escaping @Sendable () async -> String? = { nil }
    ) {
        self.terminal = terminal
        self.viewProvider = viewProvider
        self.launcher = launcher
        self.config = config
        self.workingDirectory = workingDirectory
        self.control = control
        self.tools = tools
        self.activity = activity
        self.watchList = watchList
        self.flights = flights
        self.promptContext = promptContext
        self.codexHome = codexHome
    }

    // MARK: - Türevler

    /// Codex bir turn üzerinde çalışıyor mu (top bar vurgusu).
    public var isResponding: Bool { phase == .running && status == .working }

    /// Monitörün `codex queue` adresi: yalnız ÇALIŞAN ve thread'ini bu
    /// açılışta bildirmiş Codex — kapalı thread'e bırakılan not kaybolurdu.
    public var deliveryTarget: OrchestratorDeliveryTarget? {
        guard phase == .running, let launch, launch.learnedThread, let threadID else { return nil }
        return OrchestratorDeliveryTarget(thread: threadID, codexHome: launch.codexHome)
    }

    // MARK: - Yaşam döngüsü

    /// Terminal olaylarını dinlemeye başlar (composition `start`).
    public func start() {
        consumer.start(terminal.events()) { [weak self] event in
            self?.apply(event)
        }
    }

    public func shutdown() async {
        if let terminalID { expectedExits.insert(terminalID) }
        terminal.killAll()
        consumer.stop()
        await control?.stop()
        terminalID = nil
        phase = .idle
    }

    // MARK: - Intent'ler

    /// Uygulama açılışı (Faz 2): orchestrator daha önce kullanıldıysa (kayıtlı
    /// thread var) Codex popup beklemeden arka planda sürdürülür — izlenen
    /// terminallerin raporu kullanıcı popup'ı açmadan da Codex'e ulaşsın.
    public func resumeIfUsedBefore() async {
        guard phase == .idle, let thread = await storedThreadID() else { return }
        await launchCodex(resume: thread)
    }

    /// Panel ya da popup açıldı: hiç başlamadıysa başlatır.
    public func activate() async {
        guard phase == .idle else { return }
        await launchCodex(resume: await storedThreadID())
    }

    /// Codex'i aynı konuşmayla yeniden açar (çıktıysa ya da takıldıysa).
    public func restart() async {
        guard !isLaunching else { return }
        closeCurrentTerminal()
        await launchCodex(resume: await storedThreadID())
    }

    /// Yeni konuşma: yeni thread, boş izleme listesi — yeni konuşma eski
    /// konuşmada izlemeye alınan terminalleri bilmez.
    public func newConversation() async {
        guard !isLaunching else { return }
        watchList.clear()
        forgetThread()
        closeCurrentTerminal()
        await launchCodex(resume: nil)
    }

    /// Kurulum script'ini popup'taki terminalde koşar; bitince Codex başlar.
    public func installCodex() {
        guard phase == .codexMissing else { return }
        errorMessage = nil
        // Başarıda terminal kapanır (`exited` → Codex başlar); hatada shell
        // açık kalır ki kullanıcı çıktıyı okusun.
        spawn(command: Self.installCommand + " && exit", environment: [:]) { [weak self] in
            self?.phase = .installing
        }
    }

    /// Popup açıkken terminal klavye odağını ve canlı akışı alır.
    /// Terminal henüz yoksa (Codex başlıyor) odak, terminal doğunca verilir.
    public func focusTerminal() {
        guard let terminalID else {
            focusWhenSpawned = true
            return
        }
        focusWhenSpawned = false
        terminal.setSurfaceState(.foreground, for: terminalID)
        terminal.setFocused(terminalID)
    }

    /// Activity kartının `Reply`'ı: metni Codex'in composer'ına yapıştırır
    /// (bracketed paste, Enter YOK) — kullanıcı tamamlayıp kendisi gönderir.
    public func typeIntoComposer(_ text: String) {
        guard phase == .running, let terminalID else { return }
        try? terminal.write(id: terminalID, text: Self.bracketedPaste(text))
        focusTerminal()
    }

    static func bracketedPaste(_ text: String) -> String {
        "\u{1b}[200~" + text + "\u{1b}[201~"
    }

    /// Karar 124: terminali çizen yüzey göründü/kayboldu. Terminal en az bir
    /// yüzey görünürken önde, hiçbiri yokken arka plandadır (süreç yaşar).
    /// Yüzeyler sayıldığı için popup ⇄ panel geçişinde SwiftUI'nin
    /// appear/disappear sırası sonucu değiştirmez. Odak burada verilmez —
    /// açılışta kayıtlı panel görünürken grid'deki terminalin odağı çalınmasın.
    public func setPresented(_ host: Host, _ presented: Bool) {
        if presented {
            presentedHosts.insert(host)
        } else {
            presentedHosts.remove(host)
        }
        // Görünmeyen terminale sonradan odak verilmez.
        if presentedHosts.isEmpty { focusWhenSpawned = false }
        applySurface()
    }

    private func applySurface() {
        guard let terminalID else { return }
        if presentedHosts.isEmpty {
            terminal.setFocused(nil)
            terminal.setSurfaceState(.background, for: terminalID)
        } else {
            terminal.setSurfaceState(.foreground, for: terminalID)
        }
    }

    // MARK: - Açılış

    private func launchCodex(resume thread: String?) async {
        isLaunching = true
        defer { isLaunching = false }
        phase = .starting
        errorMessage = nil
        do {
            let endpoint = try await controlEndpoint()
            let context = promptContext()
            let home = await codexHome()
            let plan = try await launcher.prepare(OrchestratorLaunchRequest(
                instructions: OrchestratorPrompt.make(projects: context.projects, watched: context.watched),
                resumeThreadID: thread,
                control: endpoint,
                codexHome: home
            ))
            spawn(command: plan.command, environment: plan.environment) { [weak self] in
                self?.launch = LaunchRecord(resumedThread: thread, codexHome: home, at: .now)
                self?.phase = .running
            }
        } catch LumiError.cliNotFound {
            phase = .codexMissing
        } catch {
            phase = .stopped
            errorMessage = (error as? LumiError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func spawn(command: String, environment: [String: String], onSpawned: () -> Void) {
        do {
            let meta = try terminal.spawn(
                repoPath: workingDirectory, task: nil, command: command, environment: environment
            )
            terminalID = meta.id
            status = meta.status
            onSpawned()
            // Restart / yeni konuşma açık bir yüzeyde olur: yeni terminal önde doğar.
            if !presentedHosts.isEmpty { applySurface() }
            if focusWhenSpawned { focusTerminal() }
        } catch {
            phase = .stopped
            errorMessage = (error as? LumiError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// MCP sunucusu ilk açılışta tembel başlar; sonrakilerde aynı uç döner.
    private func controlEndpoint() async throws -> OrchestratorControlEndpoint? {
        guard let control, let tools else { return nil }
        return try await control.start(handler: tools)
    }

    private func closeCurrentTerminal() {
        guard let terminalID else { return }
        expectedExits.insert(terminalID)
        try? terminal.kill(id: terminalID)
        self.terminalID = nil
        launch = nil
    }

    // MARK: - Terminal olayları

    func apply(_ event: TerminalEvent) {
        switch event {
        case .statusChanged(let id, let newStatus) where id == terminalID:
            status = newStatus
        case .codexSessionIDChanged(let id, let thread) where id == terminalID:
            let wasDeliverable = deliveryTarget != nil
            launch?.learnedThread = true
            ignoresStoredThread = false
            let isNewThread = thread != threadID
            threadID = thread
            if isNewThread {
                Task { await config.updateUIState { $0.orchestratorCodexThreadID = thread } }
            }
            if !wasDeliverable || isNewThread { onDeliveryTargetAvailable?() }
        case .exited(let id, let code):
            handleExit(id, code: code)
        default:
            break
        }
    }

    private func handleExit(_ id: TerminalID, code: Int32) {
        if expectedExits.remove(id) != nil { return }
        guard id == terminalID else { return }
        terminalID = nil
        status = .idle
        let finished = phase
        let record = launch
        launch = nil
        switch finished {
        case .installing:
            // Kurulum bitti: Codex artık bulunuyorsa başlar, yoksa panel geri gelir.
            Task { await self.launchCodex(resume: await self.storedThreadID()) }
        case .running where Self.resumeFailed(record):
            // Thread artık yok (silinmiş / başka hesapta): yeni konuşma açılır.
            forgetThread()
            Task { await self.launchCodex(resume: nil) }
        default:
            phase = .stopped
            errorMessage = code == 0 ? nil : "Codex exited with code \(code)."
        }
    }

    private static func resumeFailed(_ record: LaunchRecord?) -> Bool {
        guard let record, record.resumedThread != nil, !record.learnedThread else { return false }
        return ContinuousClock.now - record.at < resumeFailureWindow
    }

    private func forgetThread() {
        threadID = nil
        ignoresStoredThread = true
    }

    private func storedThreadID() async -> String? {
        if let threadID { return threadID }
        guard !ignoresStoredThread else { return nil }
        let stored = await config.uiState().orchestratorCodexThreadID
        threadID = stored
        return stored
    }
}
