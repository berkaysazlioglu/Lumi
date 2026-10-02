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

/// Orchestrator araç sözleşmesinin tek kaynağı (karar 103): MCP sunucusu
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

    /// `read_terminal` sınırları.
    public static let defaultReadLimit = 6
    public static let maxReadLimit = 30

    public static let specs: [OrchestratorToolSpec] = [
        OrchestratorToolSpec(
            name: listProjects,
            description: """
            List the user's projects as shown in Lumi's Projects panel: each project, its checkouts \
            (the project root plus managed workspaces/worktrees with their branch) and the terminals \
            running in each checkout with their status. Use this to understand where things are.
            """,
            inputSchema: #"{"type":"object","properties":{},"additionalProperties":false}"#
        ),
        OrchestratorToolSpec(
            name: listTerminals,
            description: """
            List Lumi's open terminals (Claude Code, Codex or plain shells) with id, title, project, \
            checkout/branch, provider, status and last activity. Status is one of: working, \
            needs-attention (finished a turn the user has not seen), waiting (finished, already seen), \
            awaiting-decision (blocked on a permission/question prompt), idle, error. Optionally filter \
            by a case-insensitive substring of the project name, checkout, branch, title or path.
            """,
            inputSchema: #"{"type":"object","properties":{"query":{"type":"string","description":"Optional case-insensitive filter."}},"additionalProperties":false}"#
        ),
        OrchestratorToolSpec(
            name: readTerminal,
            description: """
            Read what happened recently in one terminal. For Claude Code terminals this returns the last \
            messages of its conversation transcript (user prompts, assistant replies, tool calls); for \
            other terminals it returns the last lines of the screen. Use it to summarize what an agent \
            did, or to check whether it is asking the user something.
            """,
            inputSchema: #"{"type":"object","properties":{"terminal_id":{"type":"string","description":"Terminal id from list_terminals (a unique prefix of at least 6 characters is accepted)."},"limit":{"type":"integer","minimum":1,"maximum":30,"description":"How many recent messages to return (default 6)."}},"required":["terminal_id"],"additionalProperties":false}"#
        ),
    ]
}
