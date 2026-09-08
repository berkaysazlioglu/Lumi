import Foundation
import LumiKit

/// Claude (`~/.claude`) ve Codex (`~/.codex`) veri kökleri; env override'ları
/// (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`) Claude Code / Codex CLI ile aynı okunur.
struct AgentDataRoots: Sendable {
    let claude: URL
    let codex: URL

    init(home: URL, environment: [String: String]) {
        claude = Self.directory("CLAUDE_CONFIG_DIR", fallback: ".claude", home: home, environment: environment)
        codex = Self.directory("CODEX_HOME", fallback: ".codex", home: home, environment: environment)
    }

    /// Claude'un proje dizini adı: yol içindeki alfanümerik olmayan her karakter `-`.
    static func encodedProjectName(_ projectPath: String) -> String {
        projectPath.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "-", options: .regularExpression)
    }

    func claudeProjectDirectory(_ projectPath: String) -> URL {
        claude.appendingPathComponent("projects").appendingPathComponent(Self.encodedProjectName(projectPath))
    }

    var codexSessions: URL { codex.appendingPathComponent("sessions") }

    private static func directory(_ key: String, fallback: String, home: URL, environment: [String: String]) -> URL {
        guard let path = environment[key], !path.isEmpty else { return home.appendingPathComponent(fallback) }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
}
