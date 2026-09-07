import Foundation
import LumiKit

/// Commit mesajını `claude -p` ile üretir (karar 47). `SessionStarterService`
/// deseni: binary `BinaryLocating` ile çözülür, doğrudan spawn edilir —
/// Lumi'nin terminal oturumlarına ve kullanıcının token kotası dışında hiçbir
/// şeye dokunmaz. I/O ağırlıklı ve binary yolunu saklar → `actor`.
///
/// Bayraklar: `--model sonnet --effort low` (ölçüm: ~3 sn, ~3¢; araçlı çok
/// turn'lü deneme 46 sn / 1.7$ sürdü ve process substitution engellendi —
/// diff'i Lumi kendisi çıkarır), `--tools ""` (araçsız, tek turn),
/// `--setting-sources ""` (kullanıcı/proje ayarları ve dil talimatları
/// karışmasın), `--no-session-persistence`, `--output-format json` (sonuç
/// `result` alanından, stdout gürültüsünden bağımsız). `--bare` KULLANILMAZ:
/// keychain okumasını atladığı için "Not logged in" döner. CWD geçici dizin.
public actor ClaudeCommitMessageService: CommitMessageGenerating {
    public static let binaryName = "claude"
    /// Düşük effort'ta tipik yanıt ~8 sn; yük değişkenliğine pay.
    public static let timeout: TimeInterval = 90
    public static let effort = "low"
    /// Hız/kalite dengesi: haiku 19 sn sürdü (soğuk), sonnet 3 sn ve daha
    /// isabetli özet üretti.
    public static let model = "sonnet"

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

    public func generate(_ request: CommitMessageRequest) async throws -> String {
        guard !request.changes.isEmpty else {
            throw LumiError.commitMessageGenerationFailed(detail: "No files selected")
        }
        guard let binary = await binary() else {
            throw LumiError.cliNotFound(binary: Self.binaryName)
        }
        let output = await runner.run(
            binary,
            arguments: Self.arguments(vcsName: request.vcsName),
            currentDirectory: workingDirectory,
            standardInput: Data(CommitMessagePrompt.body(for: request).utf8),
            timeout: Self.timeout
        )
        guard let output else {
            throw LumiError.commitMessageGenerationFailed(detail: "claude -p timed out or failed to launch")
        }
        guard output.exitCode == 0 else {
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LumiError.commitMessageGenerationFailed(
                detail: detail.isEmpty ? "exit code \(output.exitCode)" : String(detail.prefix(500))
            )
        }
        let reply = try Self.resultText(fromJSON: output.stdout)
        guard let message = CommitMessagePrompt.cleanReply(reply) else {
            throw LumiError.commitMessageGenerationFailed(detail: "empty reply")
        }
        return message
    }

    static func arguments(vcsName: String) -> [String] {
        [
            "-p", CommitMessagePrompt.instruction(vcsName: vcsName),
            "--model", model,
            "--effort", effort,
            "--output-format", "json",
            "--tools", "",
            "--setting-sources", "",
            "--no-session-persistence",
        ]
    }

    /// `--output-format json` zarfı: `{"type":"result","subtype":"success",
    /// "is_error":false,"result":"…"}`. Hata alt tipinde `result` açıklamadır.
    static func resultText(fromJSON stdout: String) throws -> String {
        guard let data = stdout.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LumiError.commitMessageGenerationFailed(detail: "unreadable reply: \(stdout.prefix(200))")
        }
        let result = (object["result"] as? String) ?? ""
        if (object["is_error"] as? Bool) == true {
            throw LumiError.commitMessageGenerationFailed(detail: result.isEmpty ? "claude reported an error" : String(result.prefix(500)))
        }
        return result
    }

    private func binary() async -> String? {
        if let resolvedBinary { return resolvedBinary }
        let located = await locator.locate(Self.binaryName)
        resolvedBinary = .some(located)
        return located
    }
}
