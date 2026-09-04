import Foundation
import LumiKit

/// `BinaryLocating`in sistem implementasyonu: PATH'ten executable çözer
/// (`which` + bilinen fallback dizinleri). SystemService, usage servisleri ve
/// SessionStarter ortak kullanır (DRY).
public struct SystemBinaryLocator: BinaryLocating {
    private static let fallbackDirectories: [String] = {
        let home = NSHomeDirectory()
        return ["\(home)/.local/bin", "/usr/local/bin", "/opt/homebrew/bin"]
    }()

    private let runner: any ProcessRunning
    private let fileManager: @Sendable (String) -> Bool

    public init(
        runner: any ProcessRunning = SystemProcessRunner(),
        isExecutableFile: @escaping @Sendable (String) -> Bool = {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    ) {
        self.runner = runner
        self.fileManager = isExecutableFile
    }

    public func locate(_ name: String, timeout: TimeInterval) async -> String? {
        if let result = await runner.run(
            "/usr/bin/which", arguments: [name], timeout: timeout
        ), result.exitCode == 0 {
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty { return path }
        }
        for directory in Self.fallbackDirectories {
            let candidate = "\(directory)/\(name)"
            if fileManager(candidate) { return candidate }
        }
        return nil
    }
}
