import Foundation
import LumiKit

/// Ajan terminallerinin "bitti / karar bekliyor / hata" anlarını yakalayıp
/// özetleyerek Activity paneline düşürür (karar 103 Faz 4).
///
/// - **Tetik:** `working` → `waitingUnseen` (kullanıcının görmediği bitiş —
///   `TerminalAttention` ile aynı kural; gördüğü bitişi tekrar söylemek gürültü),
///   `working` → `error`, ve karar beklemenin başlaması. Düz shell'ler hariç.
/// - **Oturma süresi:** Claude alt ajan/compaction sırasında kısa süre
///   `waiting`'e düşüp geri dönebilir; olay `settleDelay` boyunca durum
///   değişmezse üretilir.
/// - **Özet:** son asistan mesajı deterministik okunur; kısaysa olduğu gibi,
///   uzunsa haiku ile özetlenir (başarısızsa kırpılmış metin). Karar beklemede
///   LLM'e gidilmez.
/// - **Kapı:** ayar kapalıysa ya da orchestrator hiç kullanılmadıysa hiçbir
///   şey üretilmez (token harcanmaz).
@MainActor
public final class TerminalDigestCoordinator {
    /// Bu uzunluğa kadar mesaj özetlenmeden gösterilir.
    public static let shortMessageLimit = 280
    /// LLM'siz yedekte gösterilen üst sınır.
    static let fallbackSummaryLimit = 300

    private let service: any TerminalSessionControlling
    private let terminals: TerminalListStore
    private let toolbox: OrchestratorToolbox
    private let summarizer: any TerminalDigestSummarizing
    private let feed: OrchestratorActivityFeed
    private let isEnabled: @MainActor () async -> Bool
    private let settleDelay: Duration
    private let now: @MainActor () -> Date
    private let consumer = EventConsumer(label: "orchestratorDigests")

    private var statuses: [TerminalID: TerminalStatus] = [:]
    private var settleTasks: [TerminalID: Task<Void, Never>] = [:]

    public init(
        service: any TerminalSessionControlling,
        terminals: TerminalListStore,
        toolbox: OrchestratorToolbox,
        summarizer: any TerminalDigestSummarizing,
        feed: OrchestratorActivityFeed,
        isEnabled: @escaping @MainActor () async -> Bool,
        settleDelay: Duration = .seconds(3),
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.service = service
        self.terminals = terminals
        self.toolbox = toolbox
        self.summarizer = summarizer
        self.feed = feed
        self.isEnabled = isEnabled
        self.settleDelay = settleDelay
        self.now = now
    }

    public func start() {
        consumer.start(service.events()) { [weak self] event in
            self?.apply(event)
        }
    }

    public func stop() {
        consumer.stop()
        settleTasks.values.forEach { $0.cancel() }
        settleTasks.removeAll()
    }

    // MARK: - Olaylar (testler doğrudan sürer)

    func apply(_ event: TerminalEvent) {
        switch event {
        case .statusChanged(let id, let status):
            let previous = statuses[id]
            statuses[id] = status
            if previous == .working, status == .waitingUnseen {
                schedule(id, .finished)
            } else if previous == .working, status == .error {
                schedule(id, .failed)
            } else if status == .working {
                cancel(id)
            }
        case .awaitingDecisionChanged(let id, let awaiting):
            if awaiting { schedule(id, .needsDecision) } else { cancel(id) }
        case .exited(let id, _):
            statuses[id] = nil
            cancel(id)
        case .spawned, .titleChanged, .providerChanged, .codexSessionIDChanged, .claudeSessionIDChanged,
             .bell, .writeFailed, .viewFocused, .stalled, .linkActivated:
            break
        }
    }

    private func schedule(_ id: TerminalID, _ kind: OrchestratorEvent.Kind) {
        cancel(id)
        settleTasks[id] = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.settleDelay)
            guard !Task.isCancelled, self.isStillCurrent(id, kind) else { return }
            self.settleTasks[id] = nil
            await self.produce(id, kind)
        }
    }

    private func cancel(_ id: TerminalID) {
        settleTasks.removeValue(forKey: id)?.cancel()
    }

    /// Oturma süresi sonunda olay hâlâ geçerli mi?
    private func isStillCurrent(_ id: TerminalID, _ kind: OrchestratorEvent.Kind) -> Bool {
        switch kind {
        case .finished: return statuses[id] == .waitingUnseen
        case .failed: return statuses[id] == .error
        case .needsDecision: return terminals.awaitingDecisionIDs.contains(id)
        }
    }

    private func produce(_ id: TerminalID, _ kind: OrchestratorEvent.Kind) async {
        guard let meta = terminals.meta(for: id), meta.provider != nil, await isEnabled() else { return }
        let digest = await digest(for: meta, kind: kind)
        feed.append(OrchestratorEvent(
            terminalID: meta.id, terminalTitle: meta.displayTitle, location: toolbox.location(of: meta),
            kind: kind, summary: digest.summary, needsUser: digest.needsUser, at: now()
        ))
    }

    func digest(for meta: TerminalMeta, kind: OrchestratorEvent.Kind) async -> TerminalDigest {
        if kind == .needsDecision {
            return TerminalDigest(summary: "Waiting for a permission or an answer — open the terminal to respond.", needsUser: true)
        }
        guard let message = await toolbox.lastAgentMessage(of: meta) else {
            return TerminalDigest(summary: kind == .failed ? "Stopped with an error." : "Finished its turn.", needsUser: false)
        }
        if message.count <= Self.shortMessageLimit {
            return TerminalDigest(summary: message, needsUser: Self.looksLikeQuestion(message))
        }
        do {
            return try await summarizer.summarize(agentMessage: message, terminalTitle: meta.displayTitle)
        } catch {
            return TerminalDigest(
                summary: OrchestratorToolFormat.truncated(
                    String(message.suffix(Self.fallbackSummaryLimit * 2)), to: Self.fallbackSummaryLimit
                ),
                needsUser: Self.looksLikeQuestion(message)
            )
        }
    }

    /// LLM'siz sezgi: mesaj soru işaretiyle bitiyor mu?
    static func looksLikeQuestion(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")
    }
}
