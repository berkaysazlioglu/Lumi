import Foundation
import LumiKit

/// Uzak bir Claude terminalinin controller'daki chat görünümünün durumu (karar 143 ek).
///
/// Telefonun chat hattıyla aynı akış (karar 88/104/105/130): hub `chat` / `chat_append` /
/// `chat_status` / `prompt` yayınlar; buradan `chat_send`, `prompt_respond` ve Stop için
/// Esc gider. Liste kuralları telefonunkiyle aynıdır (LumiWire'daki ortak parçalar):
/// gönderilen mesaj transcript'e düşene kadar iyimser görünür (`ChatPending`), canlı
/// metin `chatDeriveStreaming` kapısından geçer, sıralama `chatAssembleRenderMessages`'tır.
@Observable @MainActor
public final class RemoteChatSession {
    public let ref: RemoteSessionRef
    public private(set) var messages: [ChatMessage] = []
    /// Hub'ın frame bütçesi eski mesajları kesti (`Load earlier messages`).
    public private(set) var hasEarlier = false
    public private(set) var status: ChatTurnStatus = .idle
    /// Bekleyen izin / soru kartları (çözülen düşer).
    public private(set) var prompts: [ChatPrompt] = []
    /// İlk snapshot gelene kadar (ya da yeniden senkronda) true.
    public private(set) var isSyncing = true
    public private(set) var isStopping = false
    /// Bekleyen kartın taslağı (seçimler + serbest metin), kart başına.
    public private(set) var promptDrafts: [String: PromptDraft] = [:]
    /// Tam liste istendi (`loadEarlier`) — bir kez.
    public private(set) var fullHistoryRequested = false
    /// Mesaj kutusunun gönderilmemiş taslağı. Görünüm her terminal seçiminde yeniden
    /// kurulduğu için oturumda durur: başka terminale geçip dönünce kaybolmaz.
    public var composerDraft = ""

    private var pending: [ChatPending] = []
    private var pendingCounter = 0
    private var streamGate = ChatStreamGate()
    private var streaming: String?
    /// Liste hub'ın kuyruğuyla bitişik mi (snapshot'la çapalandı) — çapasız `chat_append` düşer.
    private var isLive = false
    private let service: any RemoteControllerServicing
    private var task: Task<Void, Never>?
    private var stopFallback: Task<Void, Never>?

    /// Stop'tan sonra hub turn'ün bittiğini söylemezse yerelde bu süre sonra boşa düşülür
    /// (karar 104 — telefonla aynı).
    static let stopFallbackDelay: Duration = .seconds(5)

    public init(ref: RemoteSessionRef, service: any RemoteControllerServicing) {
        self.ref = ref
        self.service = service
    }

    /// Görünümün çizdiği liste: iyimser mesajlar + transcript + canlı metin, turn'lere katlı.
    public var turns: [FoldedTurn] {
        foldChatMessages(chatAssembleRenderMessages(messages: messages, pending: pending, streaming: streaming))
    }

    /// En son bekleyen kart (görünüm tek kart gösterir).
    public var activePrompt: ChatPrompt? { prompts.last { $0.state == .pending } }

    // MARK: - Yaşam döngüsü

    /// Chat aboneliğini açar. Elde liste varsa yalnız eksikler istenir (`afterId`).
    public func start() {
        task?.cancel()
        isSyncing = true
        let cursor = syncCursor
        // Cevap (snapshot ya da `afterId`'li append) gelene kadar çapasız append'ler düşer.
        isLive = false
        let stream = service.chatEvents(hubId: ref.hubId, sessionId: ref.sessionId, afterId: cursor)
        task = Task { [weak self] in
            for await event in stream { self?.apply(event) }
        }
    }

    /// Aboneliği bırakır (hub'a `unsubscribe{mode:chat}` gider).
    public func stop() {
        task?.cancel()
        task = nil
        stopFallback?.cancel()
        isLive = false
    }

    /// Kesilen geçmişin tamamını ister (karar 131 — tam snapshot, imleçsiz).
    public func loadEarlier() {
        guard hasEarlier, !fullHistoryRequested else { return }
        fullHistoryRequested = true
        isLive = false
        task?.cancel()
        isSyncing = true
        let stream = service.chatEvents(hubId: ref.hubId, sessionId: ref.sessionId, afterId: nil)
        task = Task { [weak self] in
            for await event in stream { self?.apply(event) }
        }
    }

    // MARK: - Eylemler

    /// Mesaj gönderir; transcript'e düşene kadar listede iyimser görünür.
    public func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingCounter += 1
        pending = chatPendingAppend(current: pending, id: "pending-\(pendingCounter)", text: trimmed,
                                    baselineTailMessageId: messages.last?.id)
        service.sendChat(hubId: ref.hubId, sessionId: ref.sessionId, text: trimmed)
    }

    /// Koşan turn'ü keser: Claude'un kesme tuşu Esc'tir (Ctrl-C boştaki Claude'dan çıkar).
    public func interrupt() {
        guard status.working, !isStopping else { return }
        isStopping = true
        service.sendInput(hubId: ref.hubId, sessionId: ref.sessionId, data: Data([0x1B]))
        let startedAt = status.startedAtMs
        stopFallback?.cancel()
        stopFallback = Task { [weak self] in
            try? await Task.sleep(for: Self.stopFallbackDelay)
            guard !Task.isCancelled else { return }
            self?.applyStopFallback(startedAt: startedAt)
        }
    }

    /// Kartı cevaplar. Kart iyimser kapanmaz: hub'ın `resolved` yayını kaldırır.
    public func respond(to prompt: ChatPrompt, with answer: RemotePromptAnswer) {
        service.respondPrompt(hubId: ref.hubId, sessionId: ref.sessionId, itemId: prompt.itemId,
                              revision: prompt.revision, answer: answer)
    }

    public func draft(for prompt: ChatPrompt) -> PromptDraft {
        promptDrafts[prompt.itemId] ?? PromptDraft()
    }

    public func updateDraft(_ draft: PromptDraft, for prompt: ChatPrompt) {
        promptDrafts[prompt.itemId] = draft
    }

    // MARK: - Olaylar

    func apply(_ event: RemoteChatEvent) {
        switch event {
        case .snapshot(let list, let earlier):
            messages = list
            hasEarlier = earlier
            isLive = true
            isSyncing = false
        case .append(let list, let afterId):
            if let afterId {
                guard let anchor = messages.firstIndex(where: { $0.id == afterId }) else { return }
                messages = Array(messages[...anchor]) + list
                isLive = true
                isSyncing = false
            } else {
                guard isLive else { return }
                upsert(list)
            }
        case .status(let newStatus):
            let previousStart = status.startedAtMs
            status = newStatus
            if !newStatus.working || newStatus.startedAtMs != previousStart {
                isStopping = false
                stopFallback?.cancel()
            }
        case .prompt(let prompt):
            prompts.removeAll { $0.itemId == prompt.itemId }
            if prompt.state == .pending {
                prompts.append(prompt)
            } else {
                promptDrafts[prompt.itemId] = nil
            }
        }
        pending = chatRetireLandedPending(messages: messages, current: pending)
        recomputeStreaming()
    }

    private func upsert(_ list: [ChatMessage]) {
        var current = messages
        for message in list {
            if let index = current.firstIndex(where: { $0.id == message.id }) {
                current[index] = message
            } else {
                current.append(message)
            }
        }
        messages = current
    }

    private func recomputeStreaming() {
        let incoming = status.working ? status.streamingText : nil
        let folded = foldChatMessages(messages).map(\.message)
        let (gate, text) = chatDeriveStreaming(gate: streamGate, folded: folded, incoming: incoming,
                                               streamLive: status.working)
        streamGate = gate
        streaming = text
    }

    private func applyStopFallback(startedAt: Int?) {
        guard isStopping else { return }
        isStopping = false
        guard status.working, status.startedAtMs == startedAt else { return }
        status = .idle
        prompts = []
        recomputeStreaming()
    }

    /// Kararlı kimlikli son mesaj — `idx-N` satır konumudur, başka transcript'te eşleşebilir.
    private var syncCursor: String? {
        guard let id = messages.last?.id, !id.hasPrefix("idx-") else { return nil }
        return id
    }
}
