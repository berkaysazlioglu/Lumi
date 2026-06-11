import Foundation

/// Persona/Action YAML'larındaki `claude` bloğu (spec/13 §2.1).
public struct ClaudeAgentConfig: Sendable, Equatable {
    public var systemPrompt: String?
    public var appendSystemPrompt: String?
    public var model: String?
    public var allowedTools: [String]
    public var disallowedTools: [String]
    public var tools: String?
    public var permissionMode: String?
    public var maxTurns: Int?

    public init(
        systemPrompt: String? = nil,
        appendSystemPrompt: String? = nil,
        model: String? = nil,
        allowedTools: [String] = [],
        disallowedTools: [String] = [],
        tools: String? = nil,
        permissionMode: String? = nil,
        maxTurns: Int? = nil
    ) {
        self.systemPrompt = systemPrompt
        self.appendSystemPrompt = appendSystemPrompt
        self.model = model
        self.allowedTools = allowedTools
        self.disallowedTools = disallowedTools
        self.tools = tools
        self.permissionMode = permissionMode
        self.maxTurns = maxTurns
    }
}

public struct CodexAgentConfig: Sendable, Equatable {
    public var model: String?

    public init(model: String? = nil) {
        self.model = model
    }
}

/// İki scope (spec/13): user `~/.lumi/...`, project `<repo>/.lumi/...`.
public enum PresetScope: String, Sendable, Equatable {
    case user
    case project
}

/// YAML tabanlı rol ön ayarı (spec/13 §2). id/label zorunlu — eksikse dosya
/// sessizce atlanır (codec kuralı).
public struct Persona: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let provider: AgentProvider?
    public let claude: ClaudeAgentConfig?
    public let codex: CodexAgentConfig?
    public let scope: PresetScope

    public init(
        id: String,
        label: String,
        provider: AgentProvider? = nil,
        claude: ClaudeAgentConfig? = nil,
        codex: CodexAgentConfig? = nil,
        scope: PresetScope = .user
    ) {
        self.id = id
        self.label = label
        self.provider = provider
        self.claude = claude
        self.codex = codex
        self.scope = scope
    }
}

/// Quick Action step'leri (spec/13 §3.1).
public enum ActionStep: Sendable, Equatable {
    /// İçerik `\r` ile bitmeli (Enter).
    case write(content: String)
    /// Default timeout 10000ms; rolling buffer üzerinde regex (karar 11 düzeltmesi).
    case waitFor(pattern: String, timeoutMs: Int)
    case delay(ms: Int)

    public static let defaultWaitTimeoutMs = 10_000
}

/// YAML tabanlı otomasyon (spec/13 §3). id/label/steps zorunlu.
public struct Action: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let description: String?
    public let icon: String
    public let provider: AgentProvider?
    public let claude: ClaudeAgentConfig?
    public let codex: CodexAgentConfig?
    public let steps: [ActionStep]
    /// Kullanıcı düzenlemesi işareti — seed bu alanı görürse default'u EZMEZ.
    public let modifiedAt: String?
    public let scope: PresetScope
    /// Runtime bilgisi (defaultIds): UI rozeti + silme koruması.
    public let isDefault: Bool

    public static let defaultIcon = "Zap"

    public init(
        id: String,
        label: String,
        description: String? = nil,
        icon: String = Action.defaultIcon,
        provider: AgentProvider? = nil,
        claude: ClaudeAgentConfig? = nil,
        codex: CodexAgentConfig? = nil,
        steps: [ActionStep],
        modifiedAt: String? = nil,
        scope: PresetScope = .user,
        isDefault: Bool = false
    ) {
        self.id = id
        self.label = label
        self.description = description
        self.icon = icon
        self.provider = provider
        self.claude = claude
        self.codex = codex
        self.steps = steps
        self.modifiedAt = modifiedAt
        self.scope = scope
        self.isDefault = isDefault
    }
}

/// `.history/<id>/<timestamp>.yaml` girdisi (spec/13 §3.3-3.4).
public struct ActionVersion: Sendable, Equatable, Identifiable {
    public var id: String { timestamp }
    public let timestamp: String

    public init(timestamp: String) {
        self.timestamp = timestamp
    }
}
