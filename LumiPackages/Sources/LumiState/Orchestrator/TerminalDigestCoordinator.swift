import Foundation
import LumiKit

/// Ajan terminallerinin "bitti / karar bekliyor / hata" anlarını yakalayıp
/// özetleyerek Activity paneline düşürür (karar 114 Faz 4).
///
/// - **Kapsam:** yalnız orchestrator'ın İZLEDİĞİ Claude terminalleri
///   (`OrchestratorWatchList`) — orchestrator'ın açtığı, mesaj gönderdiği ya
///   da `watch_terminal` ile aldığı terminaller.
/// - **Tetik:** `working` → herhangi bir `waiting*` (izlenen terminalin her
///   bitişi raporlanır — kullanıcı terminale bakıyor olsa da orchestrator
///   cevabı bilmelidir), `working` → `error`, ve karar beklemenin başlaması.
/// - **Oturma süresi:** Claude alt ajan/compaction sırasında kısa süre
///   `waiting`'e düşüp geri dönebilir; olay `settleDelay` boyunca durum
///   değişmezse üretilir.
/// - **Özet:** son asistan mesajı deterministik okunur; kısaysa olduğu gibi,
///   uzunsa haiku ile özetlenir (başarısızsa kırpılmış metin). Karar beklemede
///   LLM'e gidilmez.
/// - **Kapı:** ayar kapalıysa hiçbir şey üretilmez (token harcanmaz).
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
    private let watchList: OrchestratorWatchList
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
        watchList: OrchestratorWatchList,
        isEnabled: @escaping @MainActor () async -> Bool,
        settleDelay: Duration = .seconds(3),
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.service = service
        self.terminals = terminals
        self.toolbox = toolbox
        self.summarizer = summarizer
        self.feed = feed
        self.watchList = watchList
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
            if previous == .working, status.isWaiting {
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
            watchList.forget(id)
        case .spawned(let meta):
            // Açılışta resume edilen terminal diskteki izleme kaydına bağlanır.
            watchList.adopt(meta)
        case .claudeSessionIDChanged(let id, let session):
            if let meta = terminals.meta(for: id) { watchList.adopt(meta) }
            watchList.sessionChanged(id, to: session)
        case .titleChanged, .providerChanged, .codexSessionIDChanged, .interruptInferred, .bell, .writeFailed, .viewFocused,
             .stalled, .linkActivated:
            break
        }
    }

    private func schedule(_ id: TerminalID, _ kind: OrchestratorEvent.Kind) {
        cancel(id)
        guard let meta = terminals.meta(for: id), isReportable(meta) else { return }
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
        case .finished: return statuses[id]?.isWaiting == true
        case .failed: return statuses[id] == .error
        case .needsDecision: return terminals.awaitingDecisionIDs.contains(id)
        }
    }

    private func produce(_ id: TerminalID, _ kind: OrchestratorEvent.Kind) async {
        guard let meta = terminals.meta(for: id), isReportable(meta), await isEnabled() else { return }
        let digest = await digest(for: meta, kind: kind)
        feed.append(OrchestratorEvent(
            terminalID: meta.id, terminalTitle: meta.displayTitle, location: toolbox.location(of: meta),
            kind: kind, summary: digest.summary, needsUser: digest.needsUser, at: now()
        ))
    }

    /// İzlenen bir Claude terminali mi?
    private func isReportable(_ meta: TerminalMeta) -> Bool {
        meta.provider == .claude && watchList.isWatched(meta)
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
            let digest = try await summarizer.summarize(agentMessage: message, terminalTitle: meta.displayTitle)
            // Soruyla biten mesaj haiku ne derse desin sorudur. Haiku uyarıları
            // ("test edilmedi") da soru sanabildiği için bayrağı yalnız soru
            // sinyali (`?` ya da Türkçe soru eki) taşıyan mesajda geçerlidir —
            // Türkçe ajan soruyu çoğu kez `?`'sız sorar ("… kaldırılsın mı,
            // yoksa … mi olsun.").
            let asks = Self.looksLikeQuestion(message) || (digest.needsUser && Self.containsQuestion(message))
            return TerminalDigest(summary: digest.summary, needsUser: asks)
        } catch {
            return TerminalDigest(
                summary: OrchestratorToolFormat.truncated(
                    String(message.suffix(Self.fallbackSummaryLimit * 2)), to: Self.fallbackSummaryLimit
                ),
                needsUser: Self.looksLikeQuestion(message)
            )
        }
    }

    /// LLM'siz sezgi: mesajın son satırı bir soru mu?
    static func looksLikeQuestion(_ text: String) -> Bool {
        let lastLine = text
            .split(whereSeparator: \.isNewline)
            .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lastLine.map { line in
            line.trimmingCharacters(in: .whitespaces).hasSuffix("?") || containsTurkishQuestionParticle(String(line))
        } ?? false
    }

    /// Metnin herhangi bir yerinde soru sinyali var mı (`?` ya da Türkçe soru eki)?
    static func containsQuestion(_ text: String) -> Bool {
        text.contains("?") || containsTurkishQuestionParticle(text)
    }

    /// Ayrı yazılan Türkçe soru eki: mı/mi/mu/mü ve çekimleri (mısın, miyim,
    /// musunuz, midir, mıydı…). Yalnız küçük harfli tam kelime eşleşir.
    static func containsTurkishQuestionParticle(_ text: String) -> Bool {
        text.split { !$0.isLetter }.contains { turkishQuestionParticles.contains(String($0)) }
    }

    /// Ünlü uyumuyla dört kök: mı, mi, mu, mü.
    private static let turkishQuestionParticles: Set<String> = Set(["ı", "i", "u", "ü"].flatMap { v in
        let stem = "m\(v)"
        return [stem, "\(stem)s\(v)n", "\(stem)s\(v)n\(v)z", "\(stem)y\(v)m", "\(stem)y\(v)z", "\(stem)d\(v)r", "\(stem)yd\(v)"]
    })
}
