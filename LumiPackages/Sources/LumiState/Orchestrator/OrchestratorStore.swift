import Foundation
import LumiKit
import Observation

/// Orchestrator sohbetinin tek kaynağı (karar 103).
///
/// Süreç tembel başlar: popup ilk açıldığında (`activate`) ya da ilk mesajda.
/// Popup kapanınca süreç YAŞAR — kapatmak yalnız gizler. Süreç ölürse
/// (crash, `Stop`) bir sonraki mesaj aynı konuşmayı `--resume` ile açar.
///
/// Görünen mesajlar = önceki süreçlerin transkriptten okunan geçmişi +
/// canlı sürecin journal'ı. Kullanıcı mesajı süreç yankılayana kadar
/// `pendingPrompt` olarak gösterilir.
@Observable
@MainActor
public final class OrchestratorStore {
    public enum Phase: Equatable, Sendable {
        case idle
        case starting
        case running
    }

    public private(set) var phase: Phase = .idle
    public private(set) var history: [ChatMessage] = []
    public private(set) var live = ChatJournalState()
    /// Gönderildi ama henüz süreçten yankılanmadı.
    public private(set) var pendingPrompt: String?
    /// Son başarısızlık (başlatma hatası, beklenmedik çıkış) — satır içi gösterilir.
    public private(set) var errorMessage: String?

    @ObservationIgnored private let service: any OrchestratorServicing
    @ObservationIgnored private let config: any ConfigServicing
    /// Lumi'nin MCP ucu + araç yürütücüsü (Faz 2). İkisinden biri yoksa
    /// orchestrator araçsız sohbet eder.
    @ObservationIgnored private let control: (any OrchestratorControlServing)?
    @ObservationIgnored private let tools: (any OrchestratorToolHandling)?
    @ObservationIgnored private let makeSessionID: @Sendable () -> String
    @ObservationIgnored private var sessionID: String?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    /// Her `start` yeni bir kuşaktır; eski sürecin akışı bitince yeni
    /// sürecin durumunu ezmesin.
    @ObservationIgnored private var generation = 0
    /// Bu süreçte gönderilen mesaj sayısı — `live.completedTurns` ile
    /// karşılaştırılıp "cevap bekleniyor mu?" türetilir.
    @ObservationIgnored private var sentTurns = 0

    public init(
        service: any OrchestratorServicing,
        config: any ConfigServicing,
        control: (any OrchestratorControlServing)? = nil,
        tools: (any OrchestratorToolHandling)? = nil,
        makeSessionID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.service = service
        self.config = config
        self.control = control
        self.tools = tools
        self.makeSessionID = makeSessionID
    }

    // MARK: - Türevler

    public var messages: [ChatMessage] { history + live.messages }
    public var streamingText: String? { live.streamingText }

    /// Orchestrator bir cevap üzerinde çalışıyor mu (girdi kilitlenmez, Stop görünür).
    public var isResponding: Bool {
        phase == .starting || pendingPrompt != nil || sentTurns > live.completedTurns
    }

    // MARK: - Intent'ler

    /// Popup açıldı: süreç yoksa başlat (resume'da geçmiş yüklenir).
    public func activate() async {
        guard phase == .idle else { return }
        await launch()
    }

    public func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        pendingPrompt = trimmed
        if phase == .idle { await launch() }
        guard phase == .running else {
            pendingPrompt = nil
            return
        }
        sentTurns += 1
        await service.send(trimmed)
    }

    /// Cevabı keser: süreç sonlandırılır, konuşma transkriptte kalır ve
    /// bir sonraki mesaj onu `--resume` ile sürdürür.
    public func stopResponse() async {
        generation += 1
        updatesTask?.cancel()
        await service.stop()
        settleStopped(error: nil)
    }

    /// Yeni konuşma: yeni kimlik, boş geçmiş.
    public func newConversation() async {
        generation += 1
        updatesTask?.cancel()
        await service.stop()
        let id = makeSessionID()
        sessionID = id
        await persist(id)
        settleStopped(error: nil)
        history = []
        await launch(resume: false)
    }

    public func shutdown() async {
        generation += 1
        updatesTask?.cancel()
        updatesTask = nil
        await service.stop()
        await control?.stop()
        phase = .idle
    }

    // MARK: - Süreç

    private func launch(resume: Bool? = nil) async {
        phase = .starting
        let (id, isKnown) = await currentSessionID()
        generation += 1
        let current = generation
        do {
            let endpoint = try await controlEndpoint()
            let run = try await service.start(OrchestratorLaunch(
                sessionID: id, resume: resume ?? isKnown, control: endpoint
            ))
            guard current == generation else { return }
            history = run.history
            live = ChatJournalState()
            sentTurns = 0
            phase = .running
            observe(run.updates, generation: current)
        } catch {
            guard current == generation else { return }
            settleStopped(error: (error as? LumiError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// MCP sunucusu ilk süreçte tembel açılır; sonrakilerde aynı uç döner.
    private func controlEndpoint() async throws -> OrchestratorControlEndpoint? {
        guard let control, let tools else { return nil }
        return try await control.start(handler: tools)
    }

    private func observe(_ updates: AsyncStream<ChatJournalState>, generation current: Int) {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await state in updates {
                guard let self, current == self.generation else { return }
                self.apply(state)
            }
            guard let self, current == self.generation else { return }
            // Akış kendiliğinden bitti: süreç çıktı. Cevap bekleniyorduysa
            // kullanıcı bunu görmeli.
            let wasResponding = self.isResponding
            self.settleStopped(error: wasResponding ? "Orchestrator stopped unexpectedly." : nil)
        }
    }

    private func apply(_ state: ChatJournalState) {
        live = state
        if let pending = pendingPrompt, state.messages.contains(where: { $0.isUserText(pending) }) {
            pendingPrompt = nil
        }
    }

    /// Süreç yok: canlı journal geçmişe katlanır, bir sonraki mesaj resume eder.
    private func settleStopped(error: String?) {
        if !live.messages.isEmpty, phase == .running {
            history += live.messages
        }
        live = ChatJournalState()
        sentTurns = 0
        pendingPrompt = nil
        phase = .idle
        errorMessage = error
    }

    /// Kalıcı kimlik; yoksa yenisi üretilip yazılır. `isKnown` = daha önce
    /// kaydedilmişti → konuşma resume edilir.
    private func currentSessionID() async -> (String, Bool) {
        if let sessionID { return (sessionID, true) }
        if let stored = await config.uiState().orchestratorSessionID {
            sessionID = stored
            return (stored, true)
        }
        let id = makeSessionID()
        sessionID = id
        await persist(id)
        return (id, false)
    }

    private func persist(_ id: String) async {
        await config.updateUIState { $0.orchestratorSessionID = id }
    }
}

private extension ChatMessage {
    func isUserText(_ text: String) -> Bool {
        guard role == .user else { return false }
        return blocks.contains { block in
            if case let .text(value, _) = block { return value == text }
            return false
        }
    }
}
