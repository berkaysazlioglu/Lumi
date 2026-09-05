import Foundation

public protocol AgentHistoryReading: Sendable {
    func entries(projectPath: String) async throws -> [AgentHistoryEntry]
}
