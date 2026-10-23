import Foundation

/// Session status broadcast by the Mac (docs/spec/50-remote-protocol.md snapshot payload).
public enum SessionStatus: String, Sendable, Equatable {
    case idle, working, error
    case waitingUnseen = "waiting-unseen"
    case waitingFocused = "waiting-focused"
    case waitingSeen = "waiting-seen"

    /// Reduces to the 4 phone badge states (design §2).
    public var badge: Badge {
        switch self {
        case .idle: .idle
        case .working: .working
        case .error: .error
        case .waitingUnseen, .waitingFocused, .waitingSeen: .waiting
        }
    }
}

extension SessionStatus: Decodable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // Tolerance (design §12.2): future status values must not break the stream.
        self = SessionStatus(rawValue: raw) ?? .idle
    }
}

public enum Badge: Sendable, Equatable { case idle, working, waiting, error }

public struct SessionSummary: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let repoPath: String
    public let repoName: String
    public var status: SessionStatus
    public let title: String?
    public let awaitingDecision: Bool
    public let model: String?
    /// The interactive prompt currently on screen (screen-scrape; spec 4). Rebuilds the card on reconnect.
    public let activePrompt: [Question]?
    /// Raw screen summary when no structured prompt is present (bare card context; spec 4 §K3).
    public let screenText: [String]?

    public init(id: String, repoPath: String, repoName: String,
                status: SessionStatus, title: String? = nil,
                awaitingDecision: Bool = false, model: String? = nil,
                activePrompt: [Question]? = nil, screenText: [String]? = nil) {
        self.id = id
        self.repoPath = repoPath
        self.repoName = repoName
        self.status = status
        self.title = title
        self.awaitingDecision = awaitingDecision
        self.model = model
        self.activePrompt = activePrompt
        self.screenText = screenText
    }

    private enum CodingKeys: String, CodingKey {
        case id, repoPath, repoName, status, title, awaitingDecision, model, activePrompt, screenText
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            repoPath: try c.decode(String.self, forKey: .repoPath),
            repoName: try c.decode(String.self, forKey: .repoName),
            status: try c.decode(SessionStatus.self, forKey: .status),
            title: try c.decodeIfPresent(String.self, forKey: .title),
            awaitingDecision: try c.decodeIfPresent(Bool.self, forKey: .awaitingDecision) ?? false,
            model: try c.decodeIfPresent(String.self, forKey: .model),
            activePrompt: try c.decodeIfPresent([Question].self, forKey: .activePrompt),
            screenText: try c.decodeIfPresent([String].self, forKey: .screenText)
        )
    }
}

public struct Repo: Decodable, Sendable, Equatable, Identifiable {
    public let name: String
    public let path: String
    public var id: String { path }

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public struct Persona: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public struct Snapshot: Decodable, Sendable, Equatable {
    public let sessions: [SessionSummary]
    public let repos: [Repo]
    public let personas: [Persona]

    public init(sessions: [SessionSummary], repos: [Repo], personas: [Persona]) {
        self.sessions = sessions
        self.repos = repos
        self.personas = personas
    }
}

/// Terminal session metadata (terminal-mirror protocol; relay sessions message).
public struct SessionMeta: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let repoName: String
    public let status: String
    public let title: String?
    public let model: String?
    public let cols: Int
    public let rows: Int
    public let kind: String?   // session type (e.g. "chat", "terminal"); Phase 2 — nil if absent
    /// Agent provider ("claude" | "codex"); nil for plain shell or older Mac (tree glyph).
    public let provider: String?
    /// Last activity, epoch ms; nil if omitted by an older Mac (relative-time label).
    public let lastActivityAt: Double?
    /// Awaiting a decision (permission/question prompt) separate from status; defaults
    /// to false if omitted by an older Mac (decision 105).
    public let awaitingDecision: Bool

    public init(id: String, repoName: String, status: String,
                title: String? = nil, model: String? = nil,
                cols: Int, rows: Int, kind: String? = nil,
                provider: String? = nil, lastActivityAt: Double? = nil,
                awaitingDecision: Bool = false) {
        self.id = id
        self.repoName = repoName
        self.status = status
        self.title = title
        self.model = model
        self.cols = cols
        self.rows = rows
        self.kind = kind
        self.provider = provider
        self.lastActivityAt = lastActivityAt
        self.awaitingDecision = awaitingDecision
    }

    private enum CodingKeys: String, CodingKey {
        case id, repoName, status, title, model, cols, rows, kind, provider, lastActivityAt, awaitingDecision
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            repoName: try c.decode(String.self, forKey: .repoName),
            status: try c.decode(String.self, forKey: .status),
            title: try c.decodeIfPresent(String.self, forKey: .title),
            model: try c.decodeIfPresent(String.self, forKey: .model),
            cols: try c.decode(Int.self, forKey: .cols),
            rows: try c.decode(Int.self, forKey: .rows),
            kind: try c.decodeIfPresent(String.self, forKey: .kind),
            provider: try c.decodeIfPresent(String.self, forKey: .provider),
            lastActivityAt: try c.decodeIfPresent(Double.self, forKey: .lastActivityAt),
            awaitingDecision: try c.decodeIfPresent(Bool.self, forKey: .awaitingDecision) ?? false
        )
    }

    /// Reduces the raw status string to a phone badge (same tolerance as SessionStatus).
    public var badge: Badge {
        (SessionStatus(rawValue: status) ?? .idle).badge
    }

    /// Mac's AgentActivityState mapping (decision 105): status + awaitingDecision → glyph state.
    public var activity: AgentActivity { AgentActivity(status: status, awaitingDecision: awaitingDecision) }
}

public struct CheckoutNode: Decodable, Sendable, Equatable, Identifiable {
    public let kind: String        // "original" | "workspace" (unknown tolerated)
    public let title: String
    public let branch: String?
    public let scm: String         // "git" | "plastic" | "none" (unknown tolerated)
    public let path: String
    public let agentIds: [String]
    public var id: String { path }

    public init(kind: String, title: String, branch: String?, scm: String, path: String, agentIds: [String]) {
        self.kind = kind; self.title = title; self.branch = branch
        self.scm = scm; self.path = path; self.agentIds = agentIds
    }

    private enum CodingKeys: String, CodingKey { case kind, title, branch, scm, path, agentIds }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try c.decodeIfPresent(String.self, forKey: .kind) ?? "original",
            title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
            branch: try c.decodeIfPresent(String.self, forKey: .branch),
            scm: try c.decodeIfPresent(String.self, forKey: .scm) ?? "none",
            path: try c.decode(String.self, forKey: .path),
            agentIds: try c.decodeIfPresent([String].self, forKey: .agentIds) ?? []
        )
    }
}

public struct ProjectNode: Decodable, Sendable, Equatable, Identifiable {
    public let name: String
    public let path: String
    public let checkouts: [CheckoutNode]
    /// Mac project appearance (decision 120; additive — `.none` from an older Mac).
    public let appearance: ProjectAppearance
    public var id: String { path }

    public init(name: String, path: String, checkouts: [CheckoutNode], appearance: ProjectAppearance = .none) {
        self.name = name; self.path = path; self.checkouts = checkouts; self.appearance = appearance
    }

    private enum CodingKeys: String, CodingKey { case name, path, checkouts, appearance }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
            path: try c.decode(String.self, forKey: .path),
            checkouts: try c.decodeIfPresent([CheckoutNode].self, forKey: .checkouts) ?? [],
            appearance: (try? c.decodeIfPresent(ProjectAppearance.self, forKey: .appearance)) ?? .none
        )
    }
}

/// Mac `ProjectColor` palette ids (decision 120). Unknown ids decode to `nil`.
public enum ProjectColorID: String, Sendable, Equatable, CaseIterable {
    case blue, teal, pink, orange, lime, green, fuchsia
}

/// Mac `ProjectIcon` wire form: `sf:<symbol>` or `emoji:<one emoji>`.
public enum ProjectIconID: Sendable, Equatable {
    case symbol(String)
    case emoji(String)

    public init?(wire raw: String) {
        if raw.hasPrefix("sf:"), raw.count > 3 {
            self = .symbol(String(raw.dropFirst(3)))
        } else if raw.hasPrefix("emoji:"), raw.count > 6 {
            self = .emoji(String(raw.dropFirst(6)))
        } else {
            return nil
        }
    }
}

/// Project identity mirrored from the Mac's Appearance… modal (decision 120).
public struct ProjectAppearance: Decodable, Sendable, Equatable {
    public let color: ProjectColorID?
    public let icon: ProjectIconID?
    /// Custom title of the root ("original") checkout; nil → "main".
    public let rootTitle: String?

    public static let none = ProjectAppearance()

    public init(color: ProjectColorID? = nil, icon: ProjectIconID? = nil, rootTitle: String? = nil) {
        self.color = color; self.icon = icon; self.rootTitle = rootTitle
    }

    private enum CodingKeys: String, CodingKey { case color, icon, rootTitle }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let title = try c.decodeIfPresent(String.self, forKey: .rootTitle)
        self.init(
            color: (try c.decodeIfPresent(String.self, forKey: .color)).flatMap(ProjectColorID.init(rawValue:)),
            icon: (try c.decodeIfPresent(String.self, forKey: .icon)).flatMap(ProjectIconID.init(wire:)),
            rootTitle: title?.isEmpty == false ? title : nil
        )
    }
}

/// A folder the phone may open a loose (project-less) terminal in (Mac decision 108).
public struct LooseLocation: Decodable, Sendable, Equatable, Identifiable {
    public let path: String
    public let label: String
    public var id: String { path }

    public init(path: String, label: String) {
        self.path = path; self.label = label
    }

    private enum CodingKeys: String, CodingKey { case path, label }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let path = try c.decode(String.self, forKey: .path)
        self.init(path: path, label: try c.decodeIfPresent(String.self, forKey: .label) ?? path)
    }
}

/// Mac display settings relevant to the phone's TUI rendering.
public struct MacDisplay: Decodable, Sendable, Equatable {
    /// Mac terminal font family; empty = bundled JetBrains Mono (Mac default).
    public let terminalFontFamily: String

    public static let `default` = MacDisplay(terminalFontFamily: "")

    public init(terminalFontFamily: String) { self.terminalFontFamily = terminalFontFamily }

    private enum CodingKeys: String, CodingKey { case terminalFontFamily }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(terminalFontFamily: try c.decodeIfPresent(String.self, forKey: .terminalFontFamily) ?? "")
    }
}

/// Projects ▸ Other (Mac decision 108/114): terminals opened outside any
/// project, grouped by folder. `label` is the Mac's short path (`~/Desktop`).
public struct OtherGroupNode: Decodable, Sendable, Equatable, Identifiable {
    public let path: String
    public let label: String
    public let agentIds: [String]
    public var id: String { path }

    public init(path: String, label: String, agentIds: [String]) {
        self.path = path; self.label = label; self.agentIds = agentIds
    }

    private enum CodingKeys: String, CodingKey { case path, label, agentIds }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let path = try c.decode(String.self, forKey: .path)
        self.init(
            path: path,
            label: try c.decodeIfPresent(String.self, forKey: .label) ?? path,
            agentIds: try c.decodeIfPresent([String].self, forKey: .agentIds) ?? []
        )
    }
}

public struct ProjectsSnapshot: Decodable, Sendable, Equatable {
    public let projects: [ProjectNode]
    /// Additive: an older Mac omits it → empty.
    public let others: [OtherGroupNode]
    public let addable: [Repo]
    /// Additive: where a loose terminal can be opened (home + roots); empty from an older Mac.
    public let looseLocations: [LooseLocation]
    /// Additive: Mac display settings; `.default` from an older Mac.
    public let display: MacDisplay

    public init(projects: [ProjectNode], others: [OtherGroupNode] = [], addable: [Repo],
                looseLocations: [LooseLocation] = [], display: MacDisplay = .default) {
        self.projects = projects; self.others = others; self.addable = addable
        self.looseLocations = looseLocations; self.display = display
    }

    private enum CodingKeys: String, CodingKey { case projects, others, addable, looseLocations, display }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            projects: try c.decodeIfPresent([ProjectNode].self, forKey: .projects) ?? [],
            others: try c.decodeIfPresent([OtherGroupNode].self, forKey: .others) ?? [],
            addable: try c.decodeIfPresent([Repo].self, forKey: .addable) ?? [],
            looseLocations: (try? c.decodeIfPresent([LooseLocation].self, forKey: .looseLocations)) ?? [],
            display: (try? c.decodeIfPresent(MacDisplay.self, forKey: .display)) ?? .default
        )
    }
}

/// Raw terminal byte slice (from a data or scrollback message).
/// `bytes` is the base64-decoded raw PTY data.
public struct TerminalChunk: Sendable, Equatable {
    public let sessionId: String
    public let seq: Int
    public let cols: Int?
    public let rows: Int?
    public let bytes: Data

    public init(sessionId: String, seq: Int, cols: Int? = nil, rows: Int? = nil, bytes: Data) {
        self.sessionId = sessionId
        self.seq = seq
        self.cols = cols
        self.rows = rows
        self.bytes = bytes
    }
}

/// The relay's first response to the phone; `lastSeenAt` is epoch milliseconds (relay `Date.now()`).
/// In the terminal-mirror protocol, the session list arrives in the `sessions` field (old `snapshot` removed).
public struct Welcome: Decodable, Sendable, Equatable {
    public let macOnline: Bool
    public let lastSeenAt: Double?
    /// Terminal-mirror protocol: list of active terminal sessions.
    public let sessions: [SessionMeta]?
    /// Repo list for starting a new session from the phone (from the relay room cache).
    public let repos: [Repo]?
    /// Projects tree snapshot (additive; nil if omitted by an older Mac).
    public let projects: [ProjectNode]?
    /// Addable repos (additive; nil if omitted by an older Mac).
    public let addable: [Repo]?
    /// Projects ▸ Other groups (additive; nil if omitted by an older Mac/relay).
    public let others: [OtherGroupNode]?
    /// Loose terminal locations (additive; nil if omitted by an older Mac/relay).
    public let looseLocations: [LooseLocation]?
    /// Mac display settings (additive; nil if omitted by an older Mac/relay).
    public let display: MacDisplay?

    public init(macOnline: Bool, lastSeenAt: Double?, sessions: [SessionMeta]? = nil, repos: [Repo]? = nil,
                projects: [ProjectNode]? = nil, addable: [Repo]? = nil, others: [OtherGroupNode]? = nil,
                looseLocations: [LooseLocation]? = nil, display: MacDisplay? = nil) {
        self.macOnline = macOnline
        self.lastSeenAt = lastSeenAt
        self.sessions = sessions
        self.repos = repos
        self.projects = projects
        self.addable = addable
        self.others = others
        self.looseLocations = looseLocations
        self.display = display
    }

    private enum CodingKeys: String, CodingKey {
        case macOnline, lastSeenAt, sessions, repos, projects, addable, others, looseLocations, display
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.macOnline = try c.decode(Bool.self, forKey: .macOnline)
        self.lastSeenAt = try c.decodeIfPresent(Double.self, forKey: .lastSeenAt)
        self.sessions = try c.decodeIfPresent([SessionMeta].self, forKey: .sessions)
        self.repos = try c.decodeIfPresent([Repo].self, forKey: .repos)
        self.projects = try c.decodeIfPresent([ProjectNode].self, forKey: .projects)
        self.addable = try c.decodeIfPresent([Repo].self, forKey: .addable)
        self.others = try c.decodeIfPresent([OtherGroupNode].self, forKey: .others)
        self.looseLocations = try? c.decodeIfPresent([LooseLocation].self, forKey: .looseLocations)
        self.display = try? c.decodeIfPresent(MacDisplay.self, forKey: .display)
    }
}

public struct Question: Decodable, Sendable, Equatable {
    public let header: String
    public let question: String
    public let options: [String]

    public init(header: String, question: String, options: [String]) {
        self.header = header
        self.question = question
        self.options = options
    }
}

public struct CommandResult: Decodable, Sendable, Equatable {
    public let commandId: String
    public let ok: Bool
    public let error: String?
    /// New session id returned by the Mac for start_session kind=chat (Phase 2).
    public let sessionId: String?
    /// Branch list returned by the Mac in response to the list_branches command.
    public let branches: [String]?

    public init(commandId: String, ok: Bool, error: String?, sessionId: String? = nil, branches: [String]? = nil) {
        self.commandId = commandId
        self.ok = ok
        self.error = error
        self.sessionId = sessionId
        self.branches = branches
    }
}
