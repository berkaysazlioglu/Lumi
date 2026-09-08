import LumiKit

public actor FakeAgentHistoryService: AgentHistoryServicing {
    public var result: [AgentHistoryEntry]
    public private(set) var deleted: [AgentHistoryEntry] = []
    public var deleteFailure: Error?
    public var delay: Duration = .zero
    public var failure: Error?
    public init(result: [AgentHistoryEntry] = []) { self.result = result }
    public func setResult(_ value: [AgentHistoryEntry]) { result = value }
    public func setDelay(_ value: Duration) { delay = value }
    public func setFailure(_ value: Error?) { failure = value }
    public func setDeleteFailure(_ value: Error?) { deleteFailure = value }
    public func deleteSession(_ entry: AgentHistoryEntry) async throws {
        if let deleteFailure { throw deleteFailure }
        deleted.append(entry)
        result.removeAll { $0.id == entry.id }
    }
    public func entries(projectPath: String) async throws -> [AgentHistoryEntry] {
        if delay != .zero { try await Task.sleep(for: delay) }
        if let failure { throw failure }
        return result
    }
}
