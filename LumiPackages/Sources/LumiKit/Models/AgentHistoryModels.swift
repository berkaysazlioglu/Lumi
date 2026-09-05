import Foundation

public struct AgentHistoryEntry: Identifiable, Sendable, Equatable {
    public let id: String
    public let provider: AgentProvider
    public let sessionID: String
    public let title: String
    public let preview: String?
    public let updatedAt: Date
    public let cwd: String?
    public let logPath: String

    public init(provider: AgentProvider, sessionID: String, title: String, preview: String? = nil,
                updatedAt: Date, cwd: String? = nil, logPath: String) {
        self.id = "\(provider.rawValue):\(sessionID)"
        self.provider = provider
        self.sessionID = sessionID
        self.title = title
        self.preview = preview
        self.updatedAt = updatedAt
        self.cwd = cwd
        self.logPath = logPath
    }

    public var resumeCommand: String? {
        guard sessionID.range(of: #"^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$"#, options: .regularExpression) != nil else { return nil }
        let quoted = sessionID.replacingOccurrences(of: "'", with: "'\\''")
        return provider == .claude ? "claude --resume '\(quoted)'" : "codex resume '\(quoted)'"
    }
}
