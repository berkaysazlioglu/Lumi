import Foundation
import LumiKit

/// Hızlı komutu `claude -p` ile üretir (karar 92). `ClaudeCommitMessageService`
/// deseni (karar 47) — binary `BinaryLocating` ile çözülür, `ProcessRunning`
/// ile doğrudan spawn edilir; terminal oturumlarına dokunmaz.
///
/// Farklar bilinçlidir: CWD proje köküdür ve Claude araçlıdır (Bash / Read /
/// Glob / Grep — kullanıcı kararı, keşif için komut çalıştırabilir). Araçlar
/// `--tools` ile sınırlanır ve `--allowedTools` ile onaysız verilir; `-p`
/// modunda soru soramayacağı için listede olmayan her şey reddedilir.
/// `--setting-sources ""` kullanıcı ayarlarını — dolayısıyla Lumi'nin kendi
/// hook'larını (karar 45) — dışarıda tutar ki başsız keşif oturumu bir
/// terminal durumu gibi raporlanmasın. `--no-session-persistence` Agent
/// History'yi kirletmez; `--max-budget-usd` gezinmenin maliyet tavanıdır.
public actor ClaudeQuickCommandService: QuickCommandGenerating {
    public static let binaryName = "claude"
    public static let model = "sonnet"
    public static let effort = "medium"
    /// Araçlı keşif birkaç turn sürer; karar 47'nin 90 sn'si yetmez.
    public static let timeout: TimeInterval = 300
    public static let maxBudgetUSD = "1.00"
    public static let tools = ["Bash", "Read", "Glob", "Grep"]

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

    public func generate(_ request: QuickCommandGenerationRequest) async throws -> String {
        guard !request.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LumiError.quickCommandGenerationFailed(detail: "Describe the command first")
        }
        guard let binary = await binary() else {
            throw LumiError.cliNotFound(binary: Self.binaryName)
        }
        let output = await runner.run(
            binary,
            arguments: Self.arguments(projectPath: request.projectPath),
            currentDirectory: request.projectPath,
            standardInput: Data(QuickCommandPrompt.body(for: request).utf8),
            timeout: Self.timeout
        )
        guard let output else {
            throw LumiError.quickCommandGenerationFailed(detail: "claude -p timed out or failed to launch")
        }
        guard output.exitCode == 0 else {
            // Hata zarfı stdout'ta da gelir (bütçe aşımı gibi); stderr'den daha açıklayıcıdır.
            if let envelope = Self.envelope(output.stdout) { _ = try Self.resultText(envelope) }
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LumiError.quickCommandGenerationFailed(
                detail: detail.isEmpty ? "exit code \(output.exitCode)" : String(detail.prefix(500))
            )
        }
        guard let envelope = Self.envelope(output.stdout) else {
            throw LumiError.quickCommandGenerationFailed(detail: "unreadable reply: \(output.stdout.prefix(200))")
        }
        let reply = try Self.resultText(envelope)
        guard let script = QuickCommandPrompt.extractScript(from: reply) else {
            throw LumiError.quickCommandGenerationFailed(detail: "empty reply")
        }
        return script
    }

    static func arguments(projectPath: String) -> [String] {
        let tools = Self.tools.joined(separator: ",")
        return [
            "-p",
            "--append-system-prompt", QuickCommandPrompt.systemPrompt(projectPath: projectPath),
            "--model", model,
            "--effort", effort,
            "--output-format", "json",
            "--tools", tools,
            "--allowedTools", tools,
            "--setting-sources", "",
            "--max-budget-usd", maxBudgetUSD,
            "--no-session-persistence",
        ]
    }

    /// `--output-format json` zarfı: `{"type":"result","is_error":false,"result":"…"}`.
    static func envelope(_ stdout: String) -> [String: Any]? {
        guard let data = stdout.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// `is_error` görünür hatadır (karar 47 ile aynı); hata alt tipinde
    /// `result` boş olabilir, o zaman alt tip (`error_max_budget_usd` …) söylenir.
    static func resultText(_ envelope: [String: Any]) throws -> String {
        let result = (envelope["result"] as? String) ?? ""
        guard (envelope["is_error"] as? Bool) == true else { return result }
        let subtype = envelope["subtype"] as? String ?? ""
        let detail = result.isEmpty ? (subtype.isEmpty ? "claude reported an error" : subtype) : result
        throw LumiError.quickCommandGenerationFailed(detail: String(detail.prefix(500)))
    }

    private func binary() async -> String? {
        if let resolvedBinary { return resolvedBinary }
        let located = await locator.locate(Self.binaryName)
        resolvedBinary = .some(located)
        return located
    }
}
