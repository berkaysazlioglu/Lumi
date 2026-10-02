import Foundation

/// Bir aracın MCP tanımı: ad, model için açıklama ve JSON Schema girdisi.
public struct OrchestratorToolSpec: Sendable, Equatable {
    public let name: String
    public let description: String
    /// JSON Schema nesnesi (ham JSON metni).
    public let inputSchema: String

    public init(name: String, description: String, inputSchema: String) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// Orchestrator araç sözleşmesinin tek kaynağı (karar 104): MCP sunucusu
/// `tools/list`'i buradan döner, yürütücü adları buradan eşler, Claude'a
/// verilen izin kuralı (`--allowedTools`) sunucu adından türer.
public enum OrchestratorTools {
    /// MCP sunucu adı — Claude araçları `mcp__lumi__<ad>` olarak görür.
    public static let serverName = "lumi"
    /// Sunucunun tüm araçlarına izin veren kural.
    public static var allowRule: String { "mcp__\(serverName)" }

    public static let listProjects = "list_projects"
    public static let listTerminals = "list_terminals"
    public static let readTerminal = "read_terminal"
    public static let sendToTerminal = "send_to_terminal"
    public static let startTerminal = "start_terminal"
    public static let askProject = "ask_project"
    public static let watchTerminal = "watch_terminal"
    public static let unwatchTerminal = "unwatch_terminal"

    /// `read_terminal` sınırları.
    public static let defaultReadLimit = 6
    public static let maxReadLimit = 30

    public static let specs: [OrchestratorToolSpec] = [
        OrchestratorToolSpec(
            name: listProjects,
            description: """
            List the user's projects as shown in Lumi's Projects panel: each project, its checkouts \
            (the project root plus managed workspaces/worktrees with their branch) and the Claude Code \
            terminals running in each checkout with their status and whether you watch them. Use this \
            to understand where things are.
            """,
            inputSchema: #"{"type":"object","properties":{},"additionalProperties":false}"#
        ),
        OrchestratorToolSpec(
            name: listTerminals,
            description: """
            List Lumi's open Claude Code terminals with id, title, project, checkout/branch, status, \
            whether you watch them and last activity. Status is one of: working, \
            needs-attention (finished a turn the user has not seen), waiting (finished, already seen), \
            awaiting-decision (blocked on a permission/question prompt), idle, error. Optionally filter \
            by a case-insensitive substring of the project name, checkout, branch, title or path.
            """,
            inputSchema: #"{"type":"object","properties":{"query":{"type":"string","description":"Optional case-insensitive filter."}},"additionalProperties":false}"#
        ),
        OrchestratorToolSpec(
            name: readTerminal,
            description: """
            Read what happened recently in one Claude Code terminal: the last messages of its \
            conversation transcript (user prompts, assistant replies, tool calls), or the last screen \
            lines if it has no transcript yet. Use it for details, or to check whether it is asking the \
            user something.
            """,
            inputSchema: #"{"type":"object","properties":{"terminal_id":{"type":"string","description":"Terminal id from list_terminals (a unique prefix of at least 6 characters is accepted)."},"limit":{"type":"integer","minimum":1,"maximum":30,"description":"How many recent messages to return (default 6)."}},"required":["terminal_id"],"additionalProperties":false}"#
        ),
        OrchestratorToolSpec(
            name: sendToTerminal,
            description: """
            Send a message to a Claude Code terminal's prompt as if the user typed it and pressed Enter. \
            The user must approve it in Lumi first; you get the outcome back. If the agent is busy, the \
            message is queued and delivered when it finishes its current turn. Send the user's words as \
            they asked — do not rewrite their intent. The terminal is watched from then on.
            """,
            inputSchema: #"{"type":"object","properties":{"terminal_id":{"type":"string","description":"Terminal id from list_terminals (unique prefix of 6+ characters accepted)."},"message":{"type":"string","description":"The text to send."}},"required":["terminal_id","message"],"additionalProperties":false}"#
        ),
        OrchestratorToolSpec(
            name: startTerminal,
            description: """
            Open a new Claude Code terminal in a checkout and optionally give it a first prompt. The user \
            must approve it in Lumi first. `path` must be a checkout path from list_projects (a project \
            root or one of its workspaces). Returns the new terminal's id; it is watched from then on.
            """,
            inputSchema: #"{"type":"object","properties":{"path":{"type":"string","description":"Checkout path from list_projects."},"prompt":{"type":"string","description":"Optional first message for the new agent."}},"required":["path"],"additionalProperties":false}"#
        ),
        OrchestratorToolSpec(
            name: askProject,
            description: """
            Ask a question about a project's code and docs ("summarize this project", "where is X \
            implemented?", "how is the build set up?"). A separate read-only agent explores the checkout \
            with Read/Glob/Grep (it also sees the project's CLAUDE.md) and returns only its answer, so \
            your context stays small. It cannot run commands or change files. Takes from a few seconds to \
            a few minutes; `path` must be a checkout path from list_projects.
            """,
            inputSchema: #"{"type":"object","properties":{"path":{"type":"string","description":"Checkout path from list_projects."},"question":{"type":"string","description":"The question, self-contained (the helper has no chat context)."}},"required":["path","question"],"additionalProperties":false}"#
        ),
        OrchestratorToolSpec(
            name: watchTerminal,
            description: """
            Start watching an existing Claude Code terminal: from now on Lumi adds an activity note \
            whenever it finishes a turn, waits on a decision or fails. Only watched terminals report. \
            Returns a short catch-up summary of its session so far, written by a separate helper agent.
            """,
            inputSchema: terminalIDSchema
        ),
        OrchestratorToolSpec(
            name: unwatchTerminal,
            description: "Stop watching a Claude Code terminal; its updates no longer reach you.",
            inputSchema: terminalIDSchema
        ),
    ]

    private static let terminalIDSchema = #"{"type":"object","properties":{"terminal_id":{"type":"string","description":"Terminal id from list_terminals (unique prefix of 6+ characters accepted)."}},"required":["terminal_id"],"additionalProperties":false}"#
}
