import Foundation
import LumiKit

/// `git` CLI çağrı katmanı (refactor 3.10): argv + cwd + timeout + sessiz-hata
/// politikası. `ProcessRunning` üstünde durur; parse ve iş mantığı içermez.
public struct GitCommandRunner: Sendable {
    public static let gitExecutable = "/usr/bin/git"
    public static let commandTimeout: TimeInterval = 20

    private let runner: any ProcessRunning
    private let executable: String
    private let timeout: TimeInterval

    public init(
        runner: any ProcessRunning = SystemProcessRunner(),
        executable: String = GitCommandRunner.gitExecutable,
        timeout: TimeInterval = GitCommandRunner.commandTimeout
    ) {
        self.runner = runner
        self.executable = executable
        self.timeout = timeout
    }

    public func run(
        _ arguments: [String],
        in repoPath: String,
        input: Data? = nil
    ) async -> ProcessOutput? {
        await runner.run(
            executable,
            arguments: arguments,
            currentDirectory: repoPath,
            standardInput: input,
            timeout: timeout
        )
    }

    public func runRaw(_ arguments: [String], in repoPath: String) async -> RawProcessOutput? {
        await runner.runRaw(
            executable,
            arguments: arguments,
            currentDirectory: repoPath,
            timeout: timeout
        )
    }

    /// "Boş ve sessiz" parite: UI'ya hata sızdırılmaz ama iz bırakılır.
    /// Git olmayan dizin BEKLENEN durumdur (paneller boş ve sessiz) — her tab
    /// değişiminde log gürültüsü üretmez.
    public func logQuietFailure(_ operation: String, _ output: ProcessOutput?) {
        if let output, output.stderr.contains("not a git repository") { return }
        let detail = output.map { "exit \($0.exitCode): \($0.stderr.prefix(200))" }
            ?? "timeout/launch failure"
        fputs("[lumi-git] \(operation) başarısız (sessiz): \(detail)\n", stderr)
    }
}
