import Foundation

/// PATH'ten executable çözer: `which` + bilinen fallback dizinleri.
/// SystemService ve UsageService ortak kullanır (DRY).
enum BinaryLocator {
    private static let fallbackDirectories: [String] = {
        let home = NSHomeDirectory()
        return ["\(home)/.local/bin", "/usr/local/bin", "/opt/homebrew/bin"]
    }()

    static func locate(_ name: String, timeout: TimeInterval = 5) async -> String? {
        if let result = await ProcessRunner.run(
            "/usr/bin/which", arguments: [name], timeout: timeout
        ), result.exitCode == 0 {
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty { return path }
        }
        for directory in fallbackDirectories {
            let candidate = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
