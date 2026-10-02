import Foundation
import LumiKit

/// `ask_project` (karar 103 Faz 5): orchestrator'ın "şu projeyi özetle / şu
/// projede X nerede?" sorularını, o projenin kökünde arka planda koşan
/// salt-okunur bir `claude -p` ile cevaplar. Orchestrator'ın kendi bağlamı
/// dosya içerikleriyle dolmaz; yalnız cevap döner.
///
/// Bayraklar: araçlar `Read`/`Glob`/`Grep` ile sınırlı ve onaysız
/// (`--tools` + `--allowedTools`; `-p` soru soramadığı için kalan her şey
/// reddedilir — Bash yok, yazma yok). `--setting-sources project`: projenin
/// `CLAUDE.md`'si ve `.claude/settings.json`'ı yüklenir (proje bağlamı için
/// gerekli — `""` ile yüklenmiyor, ölçüldü); kullanıcı ayarları ve dolayısıyla
/// Lumi'nin hook'ları yüklenmez. `--strict-mcp-config`: kullanıcı genelindeki
/// MCP sunucularının araç şemaları yüklenmez — ölçümde ilk çağrıya ~100 bin
/// token önbellek yazımı ekliyordu ($0.52 → $0.007). `--max-budget-usd`
/// gezinmenin maliyet tavanıdır; `--no-session-persistence` Agent History'yi
/// kirletmez.
public actor ClaudeProjectAskService: ProjectQuestionAnswering {
    public static let binaryName = "claude"
    public static let model = "sonnet"
    public static let effort = "medium"
    /// Büyük projede keşif birkaç dakika sürebilir; orchestrator'ın MCP araç
    /// zaman aşımı (15 dk) bunun üstündedir.
    public static let timeout: TimeInterval = 300
    public static let maxBudgetUSD = "1.00"
    public static let tools = ["Read", "Glob", "Grep"]

    private let runner: any ProcessRunning
    private let locator: any BinaryLocating
    private var resolvedBinary: String??

    public init(
        runner: any ProcessRunning = SystemProcessRunner(),
        locator: any BinaryLocating = SystemBinaryLocator()
    ) {
        self.runner = runner
        self.locator = locator
    }

    public func ask(projectPath: String, question: String) async throws -> ProjectAnswer {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LumiError.projectQuestionFailed(detail: "empty question") }
        guard let binary = await binary() else { throw LumiError.cliNotFound(binary: Self.binaryName) }
        let output = await runner.run(
            binary,
            arguments: Self.arguments,
            currentDirectory: projectPath,
            standardInput: Data(trimmed.utf8),
            timeout: Self.timeout
        )
        guard let output else {
            throw LumiError.projectQuestionFailed(detail: "claude -p timed out after \(Int(Self.timeout)) s or failed to launch")
        }
        // Hata zarfı (bütçe aşımı …) stdout'ta da gelir; stderr'den açıklayıcıdır.
        let envelope = ClaudePrintEnvelope(stdout: output.stdout)
        if let envelope, envelope.isError {
            throw LumiError.projectQuestionFailed(detail: envelope.errorDetail)
        }
        guard output.exitCode == 0 else {
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LumiError.projectQuestionFailed(detail: detail.isEmpty ? "exit code \(output.exitCode)" : String(detail.prefix(500)))
        }
        guard let envelope else {
            throw LumiError.projectQuestionFailed(detail: "unreadable reply: \(output.stdout.prefix(200))")
        }
        let answer = envelope.result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw LumiError.projectQuestionFailed(detail: "empty answer") }
        return ProjectAnswer(text: answer, costUSD: envelope.costUSD, durationSeconds: envelope.durationSeconds)
    }

    static let systemPrompt = """
    You are a read-only research helper inside Lumi. Another agent (the Lumi Orchestrator) \
    asks you a question about the project in the current working directory on behalf of the \
    user. Explore with Read, Glob and Grep only — you cannot run commands or change files. \
    Answer concisely and concretely: lead with the answer, cite file paths (relative to the \
    project root) for the key facts, and say plainly when something could not be found. \
    Reply in the language of the question. No preamble, no offer of further help.
    """

    static var arguments: [String] {
        let tools = Self.tools.joined(separator: ",")
        return [
            "-p",
            "--append-system-prompt", systemPrompt,
            "--model", model,
            "--effort", effort,
            "--output-format", "json",
            "--tools", tools,
            "--allowedTools", tools,
            "--setting-sources", "project",
            "--strict-mcp-config",
            "--max-budget-usd", maxBudgetUSD,
            "--no-session-persistence",
        ]
    }

    private func binary() async -> String? {
        if let resolvedBinary { return resolvedBinary }
        let located = await locator.locate(Self.binaryName)
        resolvedBinary = .some(located)
        return located
    }
}
