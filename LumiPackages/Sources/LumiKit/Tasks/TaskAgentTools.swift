import Foundation

/// Task ajanının araçları (karar 137, Faz 3): Lumi'nin task-ajanı MCP
/// sunucusu `tools/list`'i buradan döner, terminale verilen izin kuralı
/// (`--allowedTools`) buradan türer. Sunucu adı orchestrator'la aynıdır
/// (`lumi`) — prompt "the lumi MCP server" der.
public enum TaskAgentTools {
    public static let getTask = "get_task"
    public static let submitForReview = TaskAgentPrompt.submitTool

    /// `claude --allowedTools` değeri: yalnız bu iki araç, onaysız.
    public static var allowedTools: String {
        [getTask, submitForReview].map { "mcp__\(OrchestratorTools.serverName)__\($0)" }.joined(separator: ",")
    }

    public static let specs: [OrchestratorToolSpec] = [
        OrchestratorToolSpec(
            name: getTask,
            description: "Read the task you were started for: its id, title, status and description.",
            inputSchema: #"{"type":"object","properties":{},"additionalProperties":false}"#
        ),
        OrchestratorToolSpec(
            name: submitForReview,
            description: """
            Call this once the task is complete and verified (it builds, tests pass). Lumi moves the task \
            to In Review and shows your summary to the user. Do not call it for partial work; never mark \
            the task done yourself.
            """,
            inputSchema: #"{"type":"object","properties":{"summary":{"type":"string","description":"2–5 sentences: what you changed, how you verified it, anything the reviewer should look at."}},"required":["summary"],"additionalProperties":false}"#
        ),
    ]
}

/// Bir ajan terminaline verilen araç oturumu: `--mcp-config` dosyası + token.
public struct TaskAgentToolSession: Sendable, Hashable {
    /// `claude --mcp-config` için JSON dosyasının yolu (0600; token içerir).
    public let configPath: String
    public let token: String

    public init(configPath: String, token: String) {
        self.configPath = configPath
        self.token = token
    }
}

/// Task ajanlarının MCP sunucusu. Her `register` yalnız o task'e geçerli bir
/// token üretir; araç çağrıları o kaydın kapanışlarına düşer.
public protocol TaskAgentToolServing: Sendable {
    /// - Parameters:
    ///   - details: `get_task`'in döndüreceği metin.
    ///   - onSubmit: `submit_for_review(summary)` geldiğinde; dönen metin ajana yanıttır.
    func register(
        details: String,
        onSubmit: @escaping @Sendable (String) async -> String
    ) async throws -> TaskAgentToolSession
    func unregister(_ session: TaskAgentToolSession) async
}
