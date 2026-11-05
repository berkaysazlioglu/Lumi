import Foundation

/// Claude terminallerinin Mac'ten Mac'e remote araçları (karar 143, Faz 5).
/// Lumi'nin `lumi-remote` modu (karar 142) bu sunucuyu her Lumi Claude
/// terminaline tanıtır; araçlar controller'ın hub bağlantılarını kullanır.
public enum RemoteMCPTools {
    public static let serverName = "lumi-remote"

    public static let listHubs = "remote_list_hubs"
    public static let connectHub = "remote_connect_hub"
    public static let listTerminals = "remote_list_terminals"
    public static let readTerminal = "remote_read_terminal"
    public static let sendToTerminal = "remote_send_to_terminal"
    public static let startTerminal = "remote_start_terminal"
    public static let closeTerminal = "remote_close_terminal"

    private static let hubArgument = #""hub":{"type":"string","description":"Hub name or id from remote_list_hubs."}"#
    private static let terminalArgument = #""terminal_id":{"type":"string","description":"Terminal id from remote_list_terminals (a unique prefix of 6+ characters is enough)."}"#

    public static let specs: [OrchestratorToolSpec] = [
        OrchestratorToolSpec(
            name: listHubs,
            description: """
            List the other Macs (hubs) shared on this Lumi network: name, id, whether they are online \
            and whether this Mac is connected to them. Use the name or id as `hub` in the other tools.
            """,
            inputSchema: #"{"type":"object","properties":{},"additionalProperties":false}"#
        ),
        OrchestratorToolSpec(
            name: connectHub,
            description: """
            Connect to a hub. Without `password` the password the user saved in Lumi is used; ask the \
            user for it only if this fails with "password required".
            """,
            inputSchema: #"{"type":"object","properties":{"# + hubArgument + #","password":{"type":"string"}},"required":["hub"],"additionalProperties":false}"#
        ),
        OrchestratorToolSpec(
            name: listTerminals,
            description: """
            List a connected hub's projects, checkouts (with their paths) and terminals: id, title, \
            agent (claude / codex / shell) and status (running, waiting for a decision, done, idle).
            """,
            inputSchema: #"{"type":"object","properties":{"# + hubArgument + #"},"required":["hub"],"additionalProperties":false}"#
        ),
        OrchestratorToolSpec(
            name: readTerminal,
            description: """
            Read a terminal on a hub once. A Claude terminal returns its recent conversation (your \
            prompts and Claude's answers); other terminals return the last lines of the screen.
            """,
            inputSchema: #"{"type":"object","properties":{"# + hubArgument + "," + terminalArgument + #","limit":{"type":"integer","minimum":1,"maximum":200,"description":"Messages (Claude) or screen lines to return. Default 20 / 80."}},"required":["hub","terminal_id"],"additionalProperties":false}"#
        ),
        OrchestratorToolSpec(
            name: sendToTerminal,
            description: """
            Type text into a terminal on a hub. With `submit` (default true) Enter is pressed too — for a \
            Claude terminal this sends a prompt, for a shell it runs a command. Check the terminal with \
            remote_read_terminal before and after.
            """,
            inputSchema: #"{"type":"object","properties":{"# + hubArgument + "," + terminalArgument + #","text":{"type":"string"},"submit":{"type":"boolean"}},"required":["hub","terminal_id","text"],"additionalProperties":false}"#
        ),
        OrchestratorToolSpec(
            name: startTerminal,
            description: """
            Open a new terminal in a checkout on a hub (checkout path from remote_list_terminals). \
            `kind` is "claude" (default; `prompt` becomes its first message, `model` is fable / opus / \
            sonnet / haiku) or "shell". Returns the new terminal id.
            """,
            inputSchema: #"{"type":"object","properties":{"# + hubArgument + #","checkout_path":{"type":"string"},"kind":{"type":"string","enum":["claude","shell"]},"prompt":{"type":"string"},"model":{"type":"string","enum":["fable","opus","sonnet","haiku"]}},"required":["hub","checkout_path"],"additionalProperties":false}"#
        ),
        OrchestratorToolSpec(
            name: closeTerminal,
            description: "Close (kill) a terminal on a hub. Only when the user asked for it.",
            inputSchema: #"{"type":"object","properties":{"# + hubArgument + "," + terminalArgument + #"},"required":["hub","terminal_id"],"additionalProperties":false}"#
        ),
    ]
}

/// Remote araç sunucusunun uç noktası — Claude terminallerinin ortamına yazılır.
public struct RemoteMCPEndpoint: Sendable, Equatable {
    public static let urlVariable = "LUMI_REMOTE_MCP_URL"
    public static let tokenVariable = "LUMI_REMOTE_MCP_TOKEN"

    public let port: UInt16
    public let token: String

    public init(port: UInt16, token: String) {
        self.port = port
        self.token = token
    }

    public var url: String { "http://127.0.0.1:\(port)/mcp" }

    /// `lumi-remote` modunun `.mcp.json`'ının açtığı değişkenler.
    public var environment: [String: String] {
        [Self.urlVariable: url, Self.tokenVariable: token]
    }
}

public protocol RemoteMCPServing: Sendable {
    /// Sunucuyu başlatır (idempotent — çalışıyorsa aynı uç döner).
    func start(handler: any OrchestratorToolHandling) async throws -> RemoteMCPEndpoint
    func stop() async
}
