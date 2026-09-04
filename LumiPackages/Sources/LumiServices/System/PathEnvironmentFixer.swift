import Foundation
import LumiKit

/// GUI app'in minimal PATH problemi: `$SHELL -ilc 'echo -n "$PATH"'` +
/// bilinen dizinler → `setenv("PATH", …)`. Electron paritesi birebir + async
/// (design/02 §8). Startup'ta bir kez, her spawn'dan ÖNCE.
public struct PathEnvironmentFixer: Sendable {
    public static let commandTimeout: TimeInterval = 5

    private let runner: any ProcessRunning
    private let environment: @Sendable () -> [String: String]
    private let fileExists: @Sendable (String) -> Bool
    private let apply: @Sendable (String) -> Void

    public init(
        runner: any ProcessRunning = SystemProcessRunner(),
        environment: @escaping @Sendable () -> [String: String] = {
            ProcessInfo.processInfo.environment
        },
        fileExists: @escaping @Sendable (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        },
        apply: @escaping @Sendable (String) -> Void = { setenv("PATH", $0, 1) }
    ) {
        self.runner = runner
        self.environment = environment
        self.fileExists = fileExists
        self.apply = apply
    }

    public func fix() async {
        apply(await mergedPath())
    }

    /// Saf hesap (test edilebilir): birleşik, dedupe edilmiş PATH.
    func mergedPath() async -> String {
        let environment = environment()
        var entries: [String] = []

        let shell = environment["SHELL"] ?? "/bin/zsh"
        if let result = await runner.run(
            shell,
            arguments: ["-ilc", "echo -n \"$PATH\""],
            timeout: Self.commandTimeout
        ), result.exitCode == 0 {
            entries += result.stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: ":")
                .map(String.init)
        }
        entries += (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        entries += Self.knownDirectories().filter(fileExists)

        var seen = Set<String>()
        return entries.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
    }

    static func knownDirectories() -> [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/.local/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "\(home)/.nvm/current/bin",
            "\(home)/.volta/bin",
        ]
    }
}
