import LumiKit

public actor FakeAgentHistoryService: AgentHistoryReading {
    public var result: [AgentHistoryEntry]
    public var delay: Duration = .zero
    public var failure: Error?
    public init(result: [AgentHistoryEntry] = []) { self.result = result }
    public func setResult(_ value: [AgentHistoryEntry]) { result = value }
    public func setDelay(_ value: Duration) { delay = value }
    public func setFailure(_ value: Error?) { failure = value }
    public func entries(projectPath: String) async throws -> [AgentHistoryEntry] {
        if delay != .zero { try await Task.sleep(for: delay) }
        if let failure { throw failure }
        return result
    }
}
