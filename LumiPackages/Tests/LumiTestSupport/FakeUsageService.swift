import Foundation
import LumiKit

/// `UsageServicing` test ikamesi (design/00 §3 deseni). Sonuç kontrol edilebilir;
/// fetch çağrı sayısı izlenir (min-interval / load-once doğrulaması için).
public actor FakeUsageService: UsageServicing {
    public nonisolated let provider: AgentProvider

    public enum Outcome: Sendable {
        case success(UsageSnapshot)
        case failure(LumiError)
    }

    private var outcome: Outcome
    public private(set) var fetchCount = 0

    public init(provider: AgentProvider = .claude, outcome: Outcome) {
        self.provider = provider
        self.outcome = outcome
    }

    public func setOutcome(_ outcome: Outcome) {
        self.outcome = outcome
    }

    public func fetch() async throws -> UsageSnapshot {
        fetchCount += 1
        switch outcome {
        case .success(let snapshot): return snapshot
        case .failure(let error): throw error
        }
    }
}
