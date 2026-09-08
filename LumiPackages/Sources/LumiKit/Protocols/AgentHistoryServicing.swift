import Foundation

public protocol AgentHistoryReading: Sendable {
    func entries(projectPath: String) async throws -> [AgentHistoryEntry]
}

/// Oturum kaydını diskten kaldırır (karar 53): log dosyası + Claude'da
/// `<id>/` alt dizini (subagents, tool-results). Çöp kutusuna taşınır.
public protocol AgentSessionDeleting: Sendable {
    func deleteSession(_ entry: AgentHistoryEntry) async throws
}

public typealias AgentHistoryServicing = AgentHistoryReading & AgentSessionDeleting
