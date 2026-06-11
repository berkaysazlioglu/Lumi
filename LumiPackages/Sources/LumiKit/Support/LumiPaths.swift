import Foundation

/// Platform path çözümlemesi (spec/13 §Platform, karar 9).
/// Prod: `~/.lumi`; dev: `~/.lumi-dev`. Prod'da yeni dizin yoksa legacy
/// `~/.pulpo` → `~/.ai-orchestrator` yerinde kullanılır (migration değil).
public struct LumiPaths: Sendable {
    public enum Mode: Sendable, Equatable {
        case production
        case development
    }

    public let mode: Mode
    public let configDir: URL
    public let tempDir: URL

    public var configFile: URL { configDir.appendingPathComponent("config.json") }
    public var uiStateFile: URL { configDir.appendingPathComponent("ui-state.json") }
    public var personasDir: URL { configDir.appendingPathComponent("personas") }
    public var actionsDir: URL { configDir.appendingPathComponent("actions") }

    public init(
        mode: Mode,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        temporaryDirectory: URL = URL(fileURLWithPath: NSTemporaryDirectory()),
        fileManager: FileManager = .default
    ) {
        self.mode = mode
        switch mode {
        case .development:
            self.configDir = homeDirectory.appendingPathComponent(".lumi-dev")
            self.tempDir = temporaryDirectory.appendingPathComponent("lumi-dev")
        case .production:
            let primary = homeDirectory.appendingPathComponent(".lumi")
            if fileManager.fileExists(atPath: primary.path) {
                self.configDir = primary
            } else {
                let legacyCandidates = [".pulpo", ".ai-orchestrator"]
                    .map { homeDirectory.appendingPathComponent($0) }
                self.configDir = legacyCandidates.first {
                    fileManager.fileExists(atPath: $0.path)
                } ?? primary
            }
            self.tempDir = temporaryDirectory.appendingPathComponent("lumi")
        }
    }

    /// Constructor'daki `mkdir -p` semantiğinin karşılığı (spec/13).
    public func ensureDirectoriesExist(fileManager: FileManager = .default) throws {
        for directory in [configDir, tempDir] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
