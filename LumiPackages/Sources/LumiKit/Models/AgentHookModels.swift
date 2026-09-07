import Foundation

/// Hook sunucusunun dinlediği loopback uç noktası (karar 45). PTY child'ına
/// env ile verilir; hook script'i buraya POST eder.
public struct AgentHookEndpoint: Sendable, Equatable {
    public let port: UInt16
    /// Rastgele paylaşılan sır — aynı makinedeki başka bir süreç hook
    /// sahteleyemesin diye her istekte başlıkla doğrulanır.
    public let token: String

    public init(port: UInt16, token: String) {
        self.port = port
        self.token = token
    }

    /// PTY child env anahtarları — hook script'leri aynı adları okur.
    public enum EnvironmentKey {
        public static let terminalID = "LUMI_TERMINAL_ID"
        public static let port = "LUMI_AGENT_HOOK_PORT"
        public static let token = "LUMI_AGENT_HOOK_TOKEN"
    }

    /// Terminal env'ine eklenen üçlü.
    public func environment(for terminalID: TerminalID) -> [String: String] {
        [
            EnvironmentKey.terminalID: terminalID.description,
            EnvironmentKey.port: String(port),
            EnvironmentKey.token: token,
        ]
    }
}

/// Claude Code / Codex hook event adlarının tipli karşılığı. Bilinmeyen adlar
/// düşürülmez — `unknown` olarak taşınır ki yeni bir event sessizce kaybolmasın
/// (trace/log için) ama durum makinesini de etkilemesin.
public enum AgentHookEventKind: Sendable, Equatable, Hashable {
    case sessionStart
    case sessionEnd
    case userPromptSubmit
    case preToolUse
    case postToolUse
    case postToolUseFailure
    case permissionRequest
    case stop
    case stopFailure
    case subagentStart
    case subagentStop
    case teammateIdle
    case postCompact
    case unknown(String)

    public init(name: String) {
        switch name {
        case "SessionStart": self = .sessionStart
        case "SessionEnd": self = .sessionEnd
        case "UserPromptSubmit": self = .userPromptSubmit
        case "PreToolUse": self = .preToolUse
        case "PostToolUse": self = .postToolUse
        case "PostToolUseFailure": self = .postToolUseFailure
        case "PermissionRequest": self = .permissionRequest
        case "Stop": self = .stop
        case "StopFailure": self = .stopFailure
        case "SubagentStart": self = .subagentStart
        case "SubagentStop": self = .subagentStop
        case "TeammateIdle": self = .teammateIdle
        case "PostCompact": self = .postCompact
        default: self = .unknown(name)
        }
    }
}

/// Hook script'inin ilettiği tek olay — ham JSON'dan yalnız durum çıkarımı için
/// gereken alanlar süzülür (karar 45). Prompt metni gibi büyük alanlar
/// taşınmaz; UI'ya ham hook gövdesi sızmaz.
public struct AgentHookEvent: Sendable, Equatable {
    public let provider: AgentProvider
    public let terminalID: TerminalID
    public let kind: AgentHookEventKind
    /// Alt ajan/teammate olayları `agent_id` taşır; lider olaylar taşımaz.
    public let agentID: String?
    /// `TeammateIdle` yalnız `teammate_name` taşır.
    public let teammateName: String?
    public let toolName: String?
    /// `SessionStart.source` (`startup` / `resume` / `clear` / `compact`).
    public let source: String?
    /// `PostCompact.trigger` (`manual` / `auto`).
    public let trigger: String?
    /// `Stop.is_interrupt` — kullanıcı turn'ü kesti.
    public let isInterrupt: Bool
    /// `UserPromptSubmit.prompt` — yalnız harness enjeksiyonlarını ayıklamak için
    /// başı okunur (compact devamı gerçek bir kullanıcı istemi değildir).
    public let promptHead: String?
    /// `background_tasks` envanteri (Claude): lider `Stop`'ta hâlâ koşan alt
    /// ajan kimlikleri. `nil` = alan yok (eski Claude); boş = hepsi bitti.
    public let runningBackgroundAgentIDs: [String]?
    public let receivedAt: Date

    public init(
        provider: AgentProvider,
        terminalID: TerminalID,
        kind: AgentHookEventKind,
        agentID: String? = nil,
        teammateName: String? = nil,
        toolName: String? = nil,
        source: String? = nil,
        trigger: String? = nil,
        isInterrupt: Bool = false,
        promptHead: String? = nil,
        runningBackgroundAgentIDs: [String]? = nil,
        receivedAt: Date = Date()
    ) {
        self.provider = provider
        self.terminalID = terminalID
        self.kind = kind
        self.agentID = agentID
        self.teammateName = teammateName
        self.toolName = toolName
        self.source = source
        self.trigger = trigger
        self.isInterrupt = isInterrupt
        self.promptHead = promptHead
        self.runningBackgroundAgentIDs = runningBackgroundAgentIDs
        self.receivedAt = receivedAt
    }

    /// Lider (ana ajan) olayı mı — alt ajan kimliği taşımayan.
    public var isLead: Bool { agentID == nil }

    /// Orca `isAskUserQuestionTool`: Claude `AskUserQuestion`, Codex
    /// `request_user_input` — ajan bir insan cevabı bekliyor.
    public var isUserQuestionTool: Bool {
        guard let toolName else { return false }
        let normalized = toolName.lowercased().filter { $0.isLetter || $0.isNumber }
        return normalized == "askuserquestion" || normalized == "requestuserinput"
    }

    /// Harness'ın compact sonrası enjekte ettiği "devam" turu — kullanıcı
    /// yazmadı, `working`'e çevrilmez (Orca `COMPACT_CONTINUATION_PREFIX`).
    public var isCompactContinuationPrompt: Bool {
        guard let promptHead else { return false }
        return promptHead.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .hasPrefix("this session is being continued from a previous conversation")
    }

    /// Prompt başından saklanan en fazla karakter sayısı.
    public static let promptHeadLimit = 128
}

// MARK: - Ham hook JSON'undan ayrıştırma

extension AgentHookEvent {
    /// Hook script'inin stdin'den aldığı JSON gövdesini olaya çevirir.
    /// `hook_event_name` yoksa ya da gövde nesne değilse `nil` — bozuk istek.
    public static func parse(
        provider: AgentProvider,
        terminalID: TerminalID,
        body: Data,
        receivedAt: Date = Date()
    ) -> AgentHookEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: body),
              let dict = object as? [String: Any],
              let name = string(dict["hook_event_name"]) else { return nil }
        return AgentHookEvent(
            provider: provider,
            terminalID: terminalID,
            kind: AgentHookEventKind(name: name),
            agentID: string(dict["agent_id"]),
            teammateName: string(dict["teammate_name"]),
            // Codex bazı sürümlerde `name` kullanır (Orca `extractCodexToolFields`).
            toolName: string(dict["tool_name"]) ?? string(dict["name"]),
            source: string(dict["source"]),
            trigger: string(dict["trigger"]),
            isInterrupt: dict["is_interrupt"] as? Bool ?? false,
            promptHead: string(dict["prompt"]).map { String($0.prefix(promptHeadLimit)) },
            runningBackgroundAgentIDs: runningAgentTasks(dict["background_tasks"]),
            receivedAt: receivedAt
        )
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Orca `readClaudeBackgroundAgentTasks` sadeleştirmesi: yalnız
    /// `subagent`/`teammate` tipli ve bitmemiş görevlerin kimlikleri.
    private static let terminalTaskStatuses: Set<String> = [
        "completed", "complete", "done", "finished", "failed", "cancelled", "canceled", "killed", "stopped",
    ]

    private static func runningAgentTasks(_ value: Any?) -> [String]? {
        guard let items = value as? [Any] else { return nil }
        var ids: [String] = []
        for case let item as [String: Any] in items {
            let type = string(item["type"])?.lowercased() ?? ""
            guard type == "subagent" || type == "teammate" else { continue }
            let status = string(item["status"])?.lowercased() ?? ""
            guard !terminalTaskStatuses.contains(status), let id = string(item["id"]) else { continue }
            ids.append(id)
        }
        return ids
    }
}

/// Hook kurulumunun sağlayıcı başına sonucu — Settings/toast için.
public struct AgentHookInstallResult: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case installed
        case unchanged
        case removed
        case skipped(reason: String)
        case failed(detail: String)
    }

    public let provider: AgentProvider
    public let outcome: Outcome

    public init(provider: AgentProvider, outcome: Outcome) {
        self.provider = provider
        self.outcome = outcome
    }
}
