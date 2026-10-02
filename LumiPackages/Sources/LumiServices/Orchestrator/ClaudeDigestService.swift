import Foundation
import LumiKit

/// Ajan terminalinin son mesajını `claude -p --model haiku` ile 1–3 satıra
/// indirir ve "kullanıcıdan bir şey istiyor mu?" sorusunu cevaplar (karar 103
/// Faz 4). Commit mesajı servisinin (karar 47) deseni: binary `BinaryLocating`
/// ile çözülür, mesaj stdin'den gider, araçsız tek turn, kullanıcı ayarları ve
/// Lumi hook'ları yüklenmez (`--setting-sources ""`), oturum kaydedilmez.
public actor ClaudeDigestService: TerminalDigestSummarizing {
    public static let binaryName = "claude"
    public static let model = "haiku"
    public static let timeout: TimeInterval = 60
    /// Stdin'e giden mesajın üst sınırı — özet için fazlası gereksiz.
    public static let maxInputCharacters = 12_000

    private let runner: any ProcessRunning
    private let locator: any BinaryLocating
    private let workingDirectory: String
    private var resolvedBinary: String??

    public init(
        runner: any ProcessRunning = SystemProcessRunner(),
        locator: any BinaryLocating = SystemBinaryLocator(),
        workingDirectory: String = NSTemporaryDirectory()
    ) {
        self.runner = runner
        self.locator = locator
        self.workingDirectory = workingDirectory
    }

    public func summarize(agentMessage: String, terminalTitle: String) async throws -> TerminalDigest {
        guard let binary = await binary() else {
            throw LumiError.cliNotFound(binary: Self.binaryName)
        }
        let input = "Terminal: \(terminalTitle)\n\nAgent's last message:\n"
            + String(agentMessage.suffix(Self.maxInputCharacters))
        let output = await runner.run(
            binary,
            arguments: Self.arguments,
            currentDirectory: workingDirectory,
            standardInput: Data(input.utf8),
            timeout: Self.timeout
        )
        guard let output else {
            throw LumiError.digestFailed(detail: "claude -p timed out or failed to launch")
        }
        guard output.exitCode == 0 else {
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LumiError.digestFailed(detail: detail.isEmpty ? "exit code \(output.exitCode)" : String(detail.prefix(300)))
        }
        guard let envelope = ClaudePrintEnvelope(stdout: output.stdout) else {
            throw LumiError.digestFailed(detail: "unreadable reply: \(output.stdout.prefix(200))")
        }
        if envelope.isError { throw LumiError.digestFailed(detail: envelope.errorDetail) }
        let reply = envelope.result
        guard let digest = Self.parse(reply) else {
            throw LumiError.digestFailed(detail: "unreadable reply: \(reply.prefix(200))")
        }
        return digest
    }

    static let instruction = """
    You summarize the latest message of an AI coding agent for a busy developer who \
    supervises many agents. Reply with ONLY a JSON object, no prose, no code fence: \
    {"summary": "<one to three short lines in Turkish: what it did / what changed / what it asks>", \
    "needsUser": <true if the agent asks a question, wants a decision or approval, or cannot \
    continue without the user; otherwise false>}
    """

    static let arguments: [String] = [
        "-p", instruction,
        "--model", model,
        "--output-format", "json",
        "--tools", "",
        "--setting-sources", "",
        // Kullanıcı genelindeki MCP araç şemaları özet için gereksiz yük (Faz 5 ölçümü).
        "--strict-mcp-config",
        "--no-session-persistence",
    ]

    /// Cevaptaki ilk `{…}` JSON nesnesi (model kod çiti eklese de bulunur).
    static func parse(_ reply: String) -> TerminalDigest? {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let object = try? JSONSerialization.jsonObject(with: Data(reply[start...end].utf8)) as? [String: Any],
              let summary = (object["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty else { return nil }
        return TerminalDigest(summary: summary, needsUser: object["needsUser"] as? Bool ?? false)
    }

    private func binary() async -> String? {
        if let resolvedBinary { return resolvedBinary }
        let located = await locator.locate(Self.binaryName)
        resolvedBinary = .some(located)
        return located
    }
}
