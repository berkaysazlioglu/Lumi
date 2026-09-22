import Foundation
import LumiKit

/// Tanı günlüğü — telefon↔Mac boru hattının hangi sınırda koptuğunu göstermek
/// için. Kalıcı DiagLog'a her zaman yazar (boyut-tavanlı, ~/.lumi/logs/mac.log);
/// `LUMI_REMOTE_DEBUG` set ise ek olarak stderr'e de düşer. Davranışa etkisi yok.
let remoteDebugEnabled = ProcessInfo.processInfo.environment["LUMI_REMOTE_DEBUG"] != nil
func rlog(_ message: @autoclosure () -> String) {
    let text = message()
    DiagLog.shared.log("remote", text)
    if remoteDebugEnabled {
        FileHandle.standardError.write(Data("[LUMI-REMOTE] \(text)\n".utf8))
    }
}

/// LumiRemote orkestratörü (spec §4.2): config'i okur, relay bağlantısını
/// yönetir ve telefon komutlarını uygular. Servis→store sınırı: EventBroadcaster.
///
/// NOT: Terminal-piping internals (transcript watching, snapshot building) Task 5'te
/// tamamen yeniden yazılacak. Bu scaffold yalnız config/connection lifecycle'ı sağlar.
@MainActor
public final class RemoteService: RemoteServicing {
    public private(set) var state: RemoteConnectionState = .disconnected
    public private(set) var currentConfig: RemoteConfig = .defaults

    private let configService: RemoteConfigService
    private let appConfig: any ConfigServicing
    private let terminal: any TerminalServicing
    private let repos: any RepoServicing
    private let connection: any RelayConnecting
    private let commandHandler: RemoteCommandHandler
    private let broadcaster = EventBroadcaster<RemoteEvent>()
    private let chatSource: any ChatTranscriptSourcing
    /// Faz 2: Chat oturumu servisi (journal köprüsü için).
    private let chatSessions: any ChatSessionServicing
    /// Session başına chat tail task'ı (mode=chat aboneliği).
    private var chatSubscriptions: [TerminalID: Task<Void, Never>] = [:]
    /// Chat köprüsü diff durumu — oturum başına son yayınlanan mesaj id'leri ve akış bilgisi.
    private var chatBridgeState: [String: ChatBridgeState] = [:]
    /// Chat oturumu → köprü task (TerminalID olmayan sessionId keyi).
    private var chatBridgeTasks: [String: Task<Void, Never>] = [:]
    /// Mode=chat subscribe olan terminal ID'leri (hook-tabanlı turn-status guard'ı için).
    private var chatModeTerminals: Set<TerminalID> = []

    /// Faz 2: hook olay akışı + session başına turn-status reducer'ları.
    /// FACTORY olmak zorunda: AsyncStream tek geçişlidir — init'te sabit stream
    /// saklanırsa stop()→start() döngüsünde ikinci start ölü stream dinler ve
    /// hook olayları (turn-status + prompt kartları) o process'te sonsuza dek
    /// kesilir (2026-09-17 cihaz teşhisi). Her start() taze stream alır
    /// (terminal.events() ile aynı desen).
    private let hookEvents: () -> AsyncStream<AgentHookEvent>
    private let turnClock: @Sendable () -> Date
    private var turnReducers: [TerminalID: TurnStatusReducer] = [:]
    /// Faz 3: session başına etkileşimli prompt journal'ı.
    private var promptJournals: [TerminalID: PromptJournal] = [:]
    /// Faz 3.1: soru cevabı keystroke'larını 1000ms aralıkla yazan iptal-edilebilir task'lar.
    private let keystrokeScheduler: any KeystrokeScheduling
    /// Bileşen B2: dış oturumlar için transcript bul (Task 3).
    private let transcriptLocator: any TranscriptLocating
    private var promptWriteTasks: [TerminalID: Task<Void, Never>] = [:]
    private var promptSeq = 0
    private var hookTask: Task<Void, Never>?
    private var configTask: Task<Void, Never>?

    private var inboundTask: Task<Void, Never>?
    private var terminalTask: Task<Void, Never>?
    private var running = false
    private var epoch = 0

    /// Aktif abonelikler: session başına canlı-çıktı stream task'ı.
    private var subscriptions: [TerminalID: Task<Void, Never>] = [:]
    /// Session başına monoton `seq` sayacı (scrollback=0, ilk data=1, …).
    private var seqCounters: [TerminalID: Int] = [:]
    /// Set edilen modellerin son-bilinen değeri (sessions meta'sı için).
    private var modelCache: [TerminalID: String] = [:]

    public init(
        paths: LumiPaths,
        terminal: any TerminalServicing,
        repos: any RepoServicing,
        connection: (any RelayConnecting)? = nil,
        chatSource: any ChatTranscriptSourcing,
        trust: any ClaudeWorkspaceTrusting = NoopClaudeWorkspaceTrust(),
        hookEvents: @escaping () -> AsyncStream<AgentHookEvent> = { AsyncStream { _ in } },
        turnClock: @escaping @Sendable () -> Date = { Date() },
        keystrokeScheduler: any KeystrokeScheduling = LiveKeystrokeScheduler(),
        transcriptLocator: any TranscriptLocating = NoopTranscriptLocating(),
        chatSessions: any ChatSessionServicing = NoopChatSessionService(),
        workspaces: any WorkspaceServicing = NoopWorkspaceServicing(),
        config: any ConfigServicing
    ) {
        self.configService = RemoteConfigService(paths: paths)
        self.appConfig = config
        self.terminal = terminal
        self.repos = repos
        self.connection = connection ?? RelayConnection()
        self.commandHandler = RemoteCommandHandler(
            terminal: terminal, trust: trust, chatSessions: chatSessions,
            repos: repos, workspaces: workspaces, config: config)
        self.chatSource = chatSource
        self.hookEvents = hookEvents
        self.turnClock = turnClock
        self.keystrokeScheduler = keystrokeScheduler
        self.transcriptLocator = transcriptLocator
        self.chatSessions = chatSessions
    }

    public func events() -> AsyncStream<RemoteEvent> { broadcaster.stream() }

    public func start() async {
        currentConfig = await configService.ensureToken()
        guard currentConfig.enabled, !running else { return }
        guard let url = URL(string: currentConfig.relayUrl) else { return }
        running = true
        epoch &+= 1
        let myEpoch = epoch

        let inboundStream = await connection.inbound()
        guard myEpoch == epoch else { return }
        inboundTask = Task { [weak self] in
            for await inbound in inboundStream {
                await self?.handleInbound(inbound)
            }
        }
        let terminalStream = terminal.events()
        terminalTask = Task { [weak self] in
            for await event in terminalStream {
                await self?.handleTerminalEvent(event)
            }
        }
        let hookStream = hookEvents()
        hookTask = Task { [weak self] in
            rlog("hook stream dinleme BAŞLADI")
            for await event in hookStream {
                await self?.handleHookEvent(event)
            }
            rlog("hook stream dinleme BİTTİ (iptal/finish)")
        }
        let configStream = appConfig.events()
        configTask = Task { [weak self] in
            for await event in configStream {
                if case .configChanged(let old, let new) = event,
                   old.sidebarProjectPaths != new.sidebarProjectPaths || old.workspaces != new.workspaces {
                    await self?.sendProjects()
                }
            }
        }
        await connection.start(url: url, hello: ["role": "mac", "token": currentConfig.token])
        guard myEpoch == epoch else { return }
        setState(.connecting)
    }

    public func stop() {
        Task { await self.shutdown() }
    }

    private func shutdown() async {
        epoch &+= 1
        running = false
        inboundTask?.cancel(); inboundTask = nil
        terminalTask?.cancel(); terminalTask = nil
        for task in subscriptions.values { task.cancel() }
        subscriptions.removeAll()
        for task in chatSubscriptions.values { task.cancel() }
        chatSubscriptions.removeAll()
        for task in chatBridgeTasks.values { task.cancel() }
        chatBridgeTasks.removeAll()
        chatBridgeState.removeAll()
        chatModeTerminals.removeAll()
        hookTask?.cancel(); hookTask = nil
        configTask?.cancel(); configTask = nil
        turnReducers.removeAll()
        promptJournals.removeAll()
        for t in promptWriteTasks.values { t.cancel() }
        promptWriteTasks.removeAll()
        seqCounters.removeAll()
        await connection.stop()
        setState(.disconnected)
    }

    public func updateConfig(_ mutate: @Sendable (inout RemoteConfig) -> Void) async {
        var config = await configService.load()
        let old = config
        mutate(&config)
        await configService.save(config)
        currentConfig = config
        guard old != config else { return }
        if running { await shutdown() }
        if config.enabled { await start() }
    }

    public func regenerateToken() async {
        await updateConfig { $0.token = generateToken() }
    }

    // MARK: - Inbound

    private func handleInbound(_ inbound: RelayInbound) async {
        switch inbound {
        case .stateChanged(let newState):
            setState(newState)
        case .message(let type, let payload):
            rlog("inbound message type=\(type) action=\(payload["action"] as? String ?? "-") session=\(payload["sessionId"] as? String ?? "-")")
            switch type {
            case "welcome":
                await sendSessions()
                await sendRepos()
                await sendProjects()
            case "subscribe":
                await handleSubscribe(payload)
            case "unsubscribe":
                handleUnsubscribe(payload)
            case "input":
                handleInput(payload)
            case "prompt_respond":
                handlePromptRespond(payload)
            case "chat_send":
                await handleChatSend(payload)
            case "command":
                let result = await commandHandler.handle(payload)
                let createdChatSession = result.sessionId != nil
                cacheModelIfSet(payload, ok: result.ok)
                await connection.send(type: "command_result", payload: result.payload)
                // Chat oturumu yaratıldı → güncel listeyi yayınla ki telefon oturumu
                // kind:"chat" ile görsün (final review #1).
                if createdChatSession { await sendSessions() }
            default:
                break
            }
        }
    }

    // MARK: - Terminal olayları → sessions yeniden yayını

    private func handleTerminalEvent(_ event: TerminalEvent) async {
        switch event {
        case .spawned, .exited, .statusChanged:
            if case let .exited(id, _) = event {
                chatModeTerminals.remove(id)
                cancelSubscription(id)
                cancelChatSubscription(id)
                modelCache[id] = nil
                turnReducers[id] = nil
                promptJournals[id] = nil
                promptWriteTasks[id]?.cancel(); promptWriteTasks[id] = nil
            }
            await sendSessions()
            await sendProjects()
        case .titleChanged, .awaitingDecisionChanged, .bell, .providerChanged, .codexSessionIDChanged, .writeFailed, .stalled,
             .viewFocused, .linkActivated:
            break
        }
    }

    // MARK: - Sessions

    /// Mevcut terminal listesinden hafif `SessionMeta` üretir ve `sessions` yollar.
    /// NOT: Liste cols/rows'u ucuz-otoriter değil; sabit 80×24 gönderilir.
    /// Telefon emülatörünü `subscribe` sonrası gelen `scrollback` (otoriter
    /// cols/rows) ile boyutlandırır.
    private func sendSessions() async {
        let repoNames = await repoNameLookup()
        var metas: [SessionMeta] = terminal.terminals.map { meta in
            let repoName = repoNames[meta.repoPath] ?? (meta.repoPath as NSString).lastPathComponent
            return SessionMeta(
                id: meta.id.description,
                repoName: repoName,
                status: meta.status.rawValue,
                title: meta.oscTitle,
                model: modelCache[meta.id],
                cols: 80,
                rows: 24,
                // Karar 79: Claude provider'lı terminal → telefonda chat view (kind:"chat").
                // Bash/Codex/shell terminal'lar nil kalır (terminal view).
                kind: meta.provider == .claude ? "chat" : nil,
                provider: meta.provider?.rawValue,
                lastActivityAt: meta.lastActivityAt.timeIntervalSince1970 * 1000
            )
        }
        // Stream-json chat oturumları (Faz 2): kind:"chat" ile listeye eklenir —
        // telefon listede ayırt eder VE submitText'i chat_send'e yönlendirir
        // (final review #1: kind prod'da yalnız buradan set edilir).
        for chat in await chatSessions.list() {
            let repoName = repoNames[chat.repoPath] ?? (chat.repoPath as NSString).lastPathComponent
            // v1 kasıtlı: chat oturumları transcript-tail; aktivite zaman damgası ve
            // provider bilinmiyor → provider/lastActivityAt nil bırakılır, telefonda
            // boş göreli-zaman etiketi görünür.
            metas.append(SessionMeta(
                id: chat.id, repoName: repoName, status: "idle",
                title: nil, model: nil, cols: 80, rows: 24, kind: "chat"
            ))
        }
        await connection.send(type: "sessions", payload: RemoteProtocol.sessionsPayload(metas))
    }

    private func repoNameLookup() async -> [String: String] {
        var map: [String: String] = [:]
        for repo in await repos.repos() { map[repo.path] = repo.name }
        return map
    }

    /// Telefonun "yeni oturum" seçicisi için repo listesini yollar. Relay bunu room'da
    /// cache'ler → sonradan bağlanan telefon welcome ile alır; bağlı telefonlara yayınlar.
    private func sendRepos() async {
        let list = await repos.repos().map { ["name": $0.name, "path": $0.path] }
        await connection.send(type: "repos", payload: RemoteProtocol.reposPayload(list))
    }

    /// Favorites tree (karar 48–51 parite): favorited projeler → checkout'lar
    /// (original + yönetilen workspace'ler) → checkout path'ine göre gruplandırılmış ajan id'leri.
    /// v1: original checkout'un gerçek branch'i atlanır (nil) — git/plastic store'larını
    /// RemoteService'e çekmemek için; workspace checkout'ları kendi branch'lerini taşır.
    /// Ajanlar en yeni aktiviteye göre azalan sırada sıralanır.
    private func sendProjects() async {
        let cfg = await appConfig.config()
        let allRepos = await repos.repos()
        let repoByPath = Dictionary(allRepos.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let managedPaths = Set(cfg.workspaces.map(\.path))

        func agentIds(at path: String) -> [String] {
            terminal.terminals
                .filter { $0.repoPath == path }
                .sorted { $0.lastActivityAt > $1.lastActivityAt }
                .map { $0.id.description }
        }

        var projects: [[String: Any]] = []
        for favPath in cfg.sidebarProjectPaths {
            guard let repo = repoByPath[favPath] else { continue }
            var checkouts: [[String: Any]] = [[
                "kind": "original", "title": "main",
                "scm": repo.isGitRepo ? "git" : "none",
                "path": repo.path, "agentIds": agentIds(at: repo.path),
            ]]
            for ws in cfg.workspaces where ws.projectPath == favPath {
                checkouts.append([
                    "kind": "workspace", "title": ws.name, "branch": ws.branch,
                    "scm": ws.scm.rawValue, "path": ws.path, "agentIds": agentIds(at: ws.path),
                ])
            }
            projects.append(["name": repo.name, "path": repo.path, "checkouts": checkouts])
        }

        let favorited = Set(cfg.sidebarProjectPaths)
        let addable = allRepos
            .filter { !favorited.contains($0.path) && !managedPaths.contains($0.path) }
            .map { ["name": $0.name, "path": $0.path] }

        await connection.send(type: "projects", payload: RemoteProtocol.projectsPayload(projects: projects, addable: addable))
    }

    // MARK: - Subscribe / Unsubscribe

    private func handleSubscribe(_ payload: [String: Any]) async {
        guard let raw = RemoteProtocol.decodeSubscribe(payload) else { return }

        if RemoteProtocol.decodeSubscribeMode(payload) == "chat" {
            // Chat modu: raw, bir ChatSessionMeta.id olabilir (UUID string) veya terminal UUID.
            // Önce chat oturumu olup olmadığını kontrol et.
            if let stream = await chatSessions.snapshots(id: raw) {
                // Chat oturumu → journal köprüsü kur; PTY feed kurma.
                // Aynı oturuma yeniden abone olununca (MobileChatView .task(id:)
                // view yeniden görününce yeniden ateşler) eski köprü task'ini İPTAL
                // et — yoksa iki task aynı diff state'i yazıp mesajları çiftler
                // (final review #2).
                chatBridgeTasks[raw]?.cancel()
                chatBridgeState[raw] = nil   // diff sıfırla
                let task = Task { [weak self] in
                    for await snap in stream {
                        guard !Task.isCancelled else { break }
                        await self?.emitChatDiff(sessionId: raw, snap: snap)
                    }
                }
                // raw = chat oturum ID'si; chatSubscriptions için dummy terminal key kullanma,
                // bunun yerine chatBridgeTasks dict'te (sessionId string → Task) tut.
                // Ancak mevcut cancelChatSubscription TerminalID tabanlı — chat oturumları
                // için chatBridgeTasks ayrı tutulur.
                chatBridgeTasks[raw] = task
                rlog("chat subscribe: chat oturumu köprüsü kuruldu sid=\(raw.prefix(8))")
                return
            }
            // Terminal ID olarak dene
            guard let id = terminalID(from: raw) else { return }
            cancelSubscription(id)
            cancelChatSubscription(id)
            // Karar 79: Claude terminali → transcript-tail köprüsü kur (Faz 2 geri alındı).
            // Non-claude terminal → eski mirror-only davranış korunur (boş chat + idle).
            // Hook-tabanlı turn-status bu terminal için her iki durumda da aktif.
            chatModeTerminals.insert(id)
            rlog("chat subscribe: terminal sid=\(raw.prefix(8)) provider=\(terminal.terminals.first(where: { $0.id == id })?.provider?.rawValue ?? "nil")")
            await connection.send(type: "chat",
                payload: RemoteProtocol.chatPayload(sessionId: raw, messages: []))
            await emitTurnStatus(id: id, status: .idle)
            // Mevcut turn-status ve prompt'ları yayınla (yeniden bağlantı senaryosu)
            let snapshot = turnReducers[id]?.status ?? .idle
            if snapshot != .idle { await emitTurnStatus(id: id, status: snapshot) }
            for item in (promptJournals[id]?.items ?? []) where item.state == .pending {
                await emitPrompt(id: id, prompt: item)
            }
            // Karar 79: Claude provider terminali için transcript köprüsü başlat.
            // Non-claude terminaller (bash/codex/shell) mirror-only kalır.
            if let meta = terminal.terminals.first(where: { $0.id == id }), meta.provider == .claude {
                rlog("chat subscribe: claude terminali — transcript köprüsü başlatılıyor sid=\(raw.prefix(8))")
                chatSubscriptions[id] = Task { [weak self] in
                    await self?.awaitTranscript(id: id, raw: raw, meta: meta)
                }
            }
            return
        }

        // terminal mode (mevcut davranış)
        guard let id = terminalID(from: raw) else { return }
        cancelSubscription(id)
        cancelChatSubscription(id)
        await startFeedEmission(id: id, raw: raw)
    }

    /// PTY feed emisyonu (scrollback seq=0 + canlı data). Terminal modunun gövdesi;
    /// chat modu da çağırır — canlı terminal şeridi chat ekranında bu feed'den çizilir
    /// (spec 2026-09-17). Feed chat İÇERİĞİ değildir; telefon ayrı şeritte gösterir.
    private func startFeedEmission(id: TerminalID, raw: String) async {
        seqCounters[id] = 0

        // (a) scrollback (seq=0, otoriter cols/rows)
        let (data, cols, rows) = terminal.serializeScrollback(id)
        await connection.send(
            type: "scrollback",
            payload: RemoteProtocol.scrollbackPayload(sessionId: raw, seq: 0, cols: cols, rows: rows, data: data)
        )

        // (b) canlı çıktı stream'i — batch başına artan seq ile `data`.
        // subscribeOutput terminal exit'inde BİTMEZ; iptal .exited event'inde
        // (handleTerminalEvent) / unsubscribe / stop'ta explicit yapılır.
        let stream = terminal.subscribeOutput(id)
        let task = Task { [weak self] in
            for await batch in stream {
                guard !Task.isCancelled else { break }
                await self?.emitData(id: id, sessionId: raw, batch: batch)
            }
        }
        subscriptions[id] = task
    }

    private func emitChat(sessionId: String, event: ChatMirrorEvent) async {
        switch event {
        case .snapshot(let messages):
            rlog("chat snapshot gönderiliyor: sid=\(sessionId.prefix(8)) count=\(messages.count)")
            await connection.send(type: "chat",
                payload: RemoteProtocol.chatPayload(sessionId: sessionId, messages: messages))
        case .append(let messages):
            guard !messages.isEmpty else { return }
            await connection.send(type: "chat_append",
                payload: RemoteProtocol.chatAppendPayload(sessionId: sessionId, messages: messages))
        }
    }

    private func cancelChatSubscription(_ id: TerminalID) {
        chatSubscriptions[id]?.cancel()
        chatSubscriptions[id] = nil
    }

    // MARK: - Chat oturumu journal köprüsü (Faz 2)

    /// Her journal snapshot'ını diff'leyerek chat/chat_append/chat_status frame'lerine çevirir.
    /// İlk yayında (boş olsa bile) tüm mesajlar → `chat` snapshot; sonraki snapshot'larda
    /// yalnız yeni mesajlar → `chat_append`; streamingText/turnActive değişince → `chat_status`.
    private func emitChatDiff(sessionId: String, snap: ChatJournalState) async {
        let isFirstEmit = chatBridgeState[sessionId] == nil
        var prev = chatBridgeState[sessionId] ?? ChatBridgeState()

        // Mesaj diff: YENİ (id) veya İÇERİĞİ DEĞİŞMİŞ mesajlar. chat_append telefonda
        // id'ye göre upsert eder → değişmiş mesaj yeniden gönderilince yerinde güncellenir.
        let changed = snap.messages.filter { prev.sentMessages[$0.id] != $0 }
        if isFirstEmit {
            // İlk yayın: her koşulda tam snapshot (boş mesaj listesiyle dahi telefonu uyandırır)
            rlog("chat-bridge: initial snapshot sid=\(sessionId.prefix(8)) count=\(snap.messages.count)")
            await connection.send(type: "chat",
                payload: RemoteProtocol.chatPayload(sessionId: sessionId, messages: snap.messages))
        } else if !changed.isEmpty {
            if prev.sentMessages.isEmpty {
                // İlk mesajlar (ilk emit'ten sonra geldiyse): tam snapshot
                rlog("chat-bridge: snapshot sid=\(sessionId.prefix(8)) count=\(snap.messages.count)")
                await connection.send(type: "chat",
                    payload: RemoteProtocol.chatPayload(sessionId: sessionId, messages: snap.messages))
            } else {
                // Yeni + güncellenmiş mesajlar: append (upsert)
                rlog("chat-bridge: append sid=\(sessionId.prefix(8)) +\(changed.count)")
                await connection.send(type: "chat_append",
                    payload: RemoteProtocol.chatAppendPayload(sessionId: sessionId, messages: changed))
            }
        }
        prev.sentMessages = Dictionary(snap.messages.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })

        // streamingText / turnActive değişimi → chat_status
        let streamChanged = snap.streamingText != prev.lastStreaming
        let workingChanged = snap.turnActive != prev.lastWorking
        if streamChanged || workingChanged {
            let status = ChatTurnStatus(
                working: snap.turnActive,
                startedAtMs: nil,
                tool: nil,
                streamingText: snap.streamingText
            )
            rlog("chat-bridge: status sid=\(sessionId.prefix(8)) working=\(snap.turnActive) streaming=\(snap.streamingText?.prefix(20) ?? "-")")
            await connection.send(type: "chat_status",
                payload: RemoteProtocol.chatStatusPayload(sessionId: sessionId, status: status))
            prev.lastStreaming = snap.streamingText
            prev.lastWorking = snap.turnActive
        }

        chatBridgeState[sessionId] = prev
    }

    /// `chat_send` frame'i: telefon → chat oturumuna metin gönderir.
    /// Karar 79: stream-json oturumu yoksa terminal PTY'sine yaz (macOS-başlatılan Claude terminali).
    private func handleChatSend(_ payload: [String: Any]) async {
        guard let (sessionId, text) = RemoteProtocol.decodeChatSend(payload) else { return }
        rlog("chat_send: sid=\(sessionId.prefix(8)) text=\(text.prefix(40))")
        let isStreamJsonChat = await chatSessions.list().contains { $0.id == sessionId }
        if isStreamJsonChat {
            await chatSessions.send(id: sessionId, text: text)
        } else if let id = terminalID(from: sessionId) {
            // macOS-başlatılan Claude terminali chat olarak görülüyor → PTY'ye yaz.
            // Birleşik `text\r` TEK yazımda gitmemeli: Claude TUI'si paste ingest bitmeden
            // CR'ı Enter olarak yutuyor, submit tetiklenmiyor — metin composer'a yapışıyor,
            // submit bir sonraki mesaja sarkıyor. Telefon terminal yolu paritesi: önce metin,
            // settle, sonra AYRI CR (orca runtime-terminal-writer / AppModel.submitText).
            if !text.isEmpty {
                try? terminal.write(id: id, text: text)
                try? await keystrokeScheduler.sleep(.milliseconds(500))
            }
            try? terminal.write(id: id, text: "\r")
        }
    }

    /// Dış/taze oturum: transcript belirene kadar sınırlı poll (10 × 500ms).
    /// Bulanursa chatSource.stream üzerinden emitChat akışına geçer.
    private func awaitTranscript(id: TerminalID, raw: String, meta: TerminalMeta) async {
        // Lumi-spawned claude oturumu: transcript id BİLİNİR (`--session-id` ile spawn
        // anında enjekte edilir → `meta.claudeSessionID`). O transcript'i doğrudan tail
        // et. Karar 80 regresyonu: locator'ın max-by-modified sezgisi taze telefon
        // chat'inde repodaki ESKİ bir oturumu seçip bayat geçmiş gösteriyordu. Dosya
        // henüz yoksa `chatSource.stream` boş snapshot yayıp bekler (telefon boş chat
        // görür, eski değil) ve claude dosyayı yazınca append eder.
        if let known = meta.claudeSessionID {
            rlog("chat subscribe: bilinen claudeSessionID kullanılıyor sid=\(known.prefix(8)) repo=\(meta.repoPath)")
            let stream = chatSource.stream(sessionID: known, repoPath: meta.repoPath)
            for await event in stream {
                guard !Task.isCancelled else { break }
                await emitChat(sessionId: raw, event: event)
            }
            return
        }
        // Harici oturum (Rider/manuel — claudeSessionID taşımaz): locator ile en yeni
        // transcript'e bağlan (max-by-modified tek mevcut ipucu).
        for _ in 0..<10 {
            if Task.isCancelled { return }
            if let resolved = transcriptLocator.locate(repoPath: meta.repoPath) {
                rlog("chat subscribe: locator transcript buldu sid=\(resolved.prefix(8)) repo=\(meta.repoPath)")
                let stream = chatSource.stream(sessionID: resolved, repoPath: meta.repoPath)
                for await event in stream {
                    guard !Task.isCancelled else { break }
                    await emitChat(sessionId: raw, event: event)
                }
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        rlog("chat subscribe: transcript bulunamadı, chat-unavailable kalıyor repo=\(meta.repoPath)")
    }

    // MARK: - Turn status (Faz 2)

    private func handleHookEvent(_ event: AgentHookEvent) async {
        let id = event.terminalID
        let reducer = turnReducers[id] ?? {
            let r = TurnStatusReducer(now: turnClock)
            turnReducers[id] = r
            return r
        }()
        // Reducer + journal abone olunmasa da ilerler (subscribe snapshot doğruluğu).
        let status = reducer.reduce(event)
        let journal = promptJournals[id] ?? {
            // weak: journal self'e ait; strong olsa self→dict→journal→closure→self döngüsü olur.
            let j = PromptJournal(seq: { [weak self] in
                guard let self else { return 0 }
                self.promptSeq += 1
                return self.promptSeq
            })
            promptJournals[id] = j
            return j
        }()
        let changedPrompts = journal.reduce(event)
        // TANI (Faz 3.1 kart hatası): her hook olayının prompt yoluna etkisi.
        rlog("hook: kind=\(event.kind) tool=\(event.toolName ?? "-") isLead=\(event.isLead) hasInput=\(event.toolInput != nil) sub=\(chatModeTerminals.contains(id)) changedPrompts=\(changedPrompts.count)")
        guard chatModeTerminals.contains(id) else { return }
        if let status { await emitTurnStatus(id: id, status: status) }
        for item in changedPrompts {
            rlog("prompt emit: kind=\(item.kind) state=\(item.state) itemId=\(item.itemId.prefix(12)) opts=\(item.options.count)")
            await emitPrompt(id: id, prompt: item)
        }
    }

    private func emitTurnStatus(id: TerminalID, status: ChatTurnStatus) async {
        await connection.send(
            type: "chat_status",
            payload: RemoteProtocol.chatStatusPayload(sessionId: id.description, status: status)
        )
    }

    private func emitPrompt(id: TerminalID, prompt: ChatPrompt) async {
        await connection.send(
            type: "prompt",
            payload: RemoteProtocol.promptPayload(sessionId: id.description, prompt: prompt)
        )
    }

    /// Telefon cevabını PTY'ye ulaştırır. `selections` varsa Faz 3.1 soru yolu (paced);
    /// yoksa Faz 3 approval (ve legacy tek-soru) optionId → tek keystroke.
    private func handlePromptRespond(_ payload: [String: Any]) {
        if payload["selections"] != nil { handleQuestionRespond(payload); return }
        guard let r = RemoteProtocol.decodePromptRespond(payload),
              let id = terminalID(from: r.sessionId),
              let journal = promptJournals[id],
              let item = journal.items.first(where: { $0.itemId == r.itemId }),
              item.state == .pending, item.revision == r.expectedRevision,
              let keys = keystroke(for: item, optionId: r.optionId) else { return }
        terminal.writeInput(keys, to: id)
        if let resolved = journal.resolve(itemId: r.itemId, optionId: r.optionId) {
            Task { await emitPrompt(id: id, prompt: resolved) }
        }
    }

    /// Faz 3.1: soru cevabı (selections) → buildAskAnswerKeys → key group'ları 1000ms aralıkla PTY.
    private func handleQuestionRespond(_ payload: [String: Any]) {
        guard let r = RemoteProtocol.decodePromptRespondSelections(payload),
              let id = terminalID(from: r.sessionId),
              let journal = promptJournals[id],
              let item = journal.items.first(where: { $0.itemId == r.itemId }),
              item.state == .pending, item.revision == r.expectedRevision,
              item.kind == .question else { return }
        // Codex provider wiring ertelendi (spec): Claude buildAskAnswerKeys.
        let groups = buildAskAnswerKeys(questions: askInputs(from: item), selections: r.selections)
        guard !groups.isEmpty else { return }
        writeKeyGroups(id: id, groups: groups)
        if let resolved = journal.resolve(itemId: r.itemId, optionId: "submitted") {
            Task { await emitPrompt(id: id, prompt: resolved) }
        }
    }

    /// ChatPrompt'tan buildAskAnswerKeys girdisi: gruplu → questions; tek-soru → flat title/options.
    private func askInputs(from item: ChatPrompt) -> [AskQuestionInput] {
        if !item.questions.isEmpty {
            return item.questions.map {
                AskQuestionInput(question: $0.question, header: $0.header,
                                 multiSelect: $0.multiSelect, optionLabels: $0.options.map(\.label))
            }
        }
        return [AskQuestionInput(question: item.title, header: nil,
                                 multiSelect: item.multiSelect, optionLabels: item.options.map(\.label))]
    }

    /// orca pacing: her grubu 1000ms aralıkla, iptal-edilebilir yazar (@MainActor).
    private func writeKeyGroups(id: TerminalID, groups: [KeyGroup]) {
        promptWriteTasks[id]?.cancel()
        let scheduler = keystrokeScheduler
        promptWriteTasks[id] = Task { [weak self] in
            for (i, group) in groups.enumerated() {
                if Task.isCancelled { return }   // her gruptan önce (ilk grup dahil) iptal kontrolü
                if i > 0 { try? await scheduler.sleep(.milliseconds(1000)) }
                if Task.isCancelled { return }
                self?.writeGroup(group, to: id)
            }
            // Bitmiş task'ı dict'ten temizlemeyiz: yeni cevap replace, .exited/shutdown cancel eder.
            // (Kendini temizlemek daha yeni bir task'ın handle'ını silme riskini doğurur — review T5.)
        }
    }

    private func writeGroup(_ group: KeyGroup, to id: TerminalID) {
        let data: Data
        switch group {
        case .raw(let s): data = Data(s.utf8)
        case .text(let s): data = Data(("\u{1b}[200~" + s + "\u{1b}[201~").utf8)  // bracketed paste
        }
        terminal.writeInput(data, to: id)
    }

    /// orca keystroke haritası (kesin): allow=byte 0x31 ('1'), deny=0x1b (ESC),
    /// question index i (0-tabanlı) → byte 0x31+i ('1'…'9'). Trailing Enter yok.
    private func keystroke(for item: ChatPrompt, optionId: String) -> Data? {
        switch item.kind {
        case .approval:
            if optionId == "allow" { return Data([0x31]) }
            if optionId == "deny" { return Data([0x1b]) }
            return nil
        case .question:
            guard let i = item.options.firstIndex(where: { $0.id == optionId }), i < 9 else { return nil }
            return Data([UInt8(0x31 + i)])
        }
    }

    private func emitData(id: TerminalID, sessionId: String, batch: Data) async {
        guard subscriptions[id] != nil else { return }
        let seq = (seqCounters[id] ?? 0) + 1
        seqCounters[id] = seq
        await connection.send(
            type: "data",
            payload: RemoteProtocol.dataPayload(sessionId: sessionId, seq: seq, data: batch)
        )
    }

    private func handleUnsubscribe(_ payload: [String: Any]) {
        guard let raw = RemoteProtocol.decodeSubscribe(payload) else { return }
        // Chat oturumu bridge task'ını iptal et
        chatBridgeTasks[raw]?.cancel()
        chatBridgeTasks[raw] = nil
        chatBridgeState[raw] = nil
        // Terminal aboneliğini iptal et
        if let id = terminalID(from: raw) {
            chatModeTerminals.remove(id)
            cancelSubscription(id)
            cancelChatSubscription(id)
        }
    }

    private func cancelSubscription(_ id: TerminalID) {
        subscriptions[id]?.cancel()
        subscriptions[id] = nil
        seqCounters[id] = nil
    }

    // MARK: - Input

    private func handleInput(_ payload: [String: Any]) {
        guard let (raw, data) = RemoteProtocol.decodeInput(payload),
              let id = terminalID(from: raw) else { return }
        terminal.writeInput(data, to: id)
    }

    // MARK: - Yardımcılar

    /// sessionId string'i (meta.id.description = UUID) → TerminalID.
    /// Parse edilemeyen id güvenle yok sayılır.
    private func terminalID(from raw: String) -> TerminalID? {
        guard let uuid = UUID(uuidString: raw) else { return nil }
        return TerminalID(raw: uuid)
    }

    /// set_model komutu başarılıysa modeli cache'le (sessions meta'sı için).
    private func cacheModelIfSet(_ payload: [String: Any], ok: Bool) {
        guard ok,
              payload["action"] as? String == "set_model",
              let model = payload["model"] as? String,
              let raw = payload["sessionId"] as? String,
              let id = terminalID(from: raw) else { return }
        modelCache[id] = model
    }

    /// Test hook'u — verilen session'ın aktif canlı-çıktı task'ı var mı.
    func hasActiveSubscription(_ id: TerminalID) -> Bool {
        subscriptions[id] != nil
    }

    /// Test hook'u — verilen session'ın aktif chat tail task'ı var mı.
    func hasActiveChatSubscription(_ id: TerminalID) -> Bool {
        chatSubscriptions[id] != nil
    }

    // MARK: - Yardımcılar

    private func setState(_ newState: RemoteConnectionState) {
        guard state != newState else { return }
        state = newState
        broadcaster.send(.stateChanged(newState))
    }

    /// Test hook'u — verilen chat sessionId'si için aktif köprü task'ı var mı.
    func hasActiveChatBridgeTask(_ sessionId: String) -> Bool {
        chatBridgeTasks[sessionId] != nil
    }
}

// MARK: - Chat köprüsü yardımcı tipler

/// Oturum başına diff hesaplamak için tutulan son-bilinen durum.
private struct ChatBridgeState {
    /// id → en son gönderilen mesaj (içerik dahil). Yalnız `Set<String>` id tutmak
    /// içerik GÜNCELLEMELERİNİ düşürüyordu: partial assistant snapshot'ları aynı id ile
    /// büyür; ilk (kısa) sürüm gidip güncellemeler gitmiyordu → canlıda bayat mesaj,
    /// reopen (tam snapshot) düzeltiyordu. Mesajı tutup eşitlikle diff'liyoruz.
    var sentMessages: [String: ChatMessage] = [:]
    var lastStreaming: String? = nil
    var lastWorking: Bool = false
}
