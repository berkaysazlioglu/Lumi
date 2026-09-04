import Foundation
import LumiKit

/// `UsageServicing` test ikamesi (design/00 §3 deseni). Sonuç kontrol edilebilir;
/// fetch çağrı sayısı izlenir (min-interval / load-once doğrulaması için).
///
/// `UsageCacheInvalidating`'i de karşılar (K38-A): manuel yenilemenin cache'i
/// gerçekten geçersizlediğini doğrulayan testler `invalidateCount`'a bakar.
public actor FakeUsageService: UsageServicing, UsageCacheInvalidating {
    public nonisolated let provider: AgentProvider

    public enum Outcome: Sendable {
        case success(UsageSnapshot)
        case failure(LumiError)
    }

    private var outcome: Outcome
    public private(set) var fetchCount = 0
    public private(set) var invalidateCount = 0

    public init(provider: AgentProvider = .claude, outcome: Outcome) {
        self.provider = provider
        self.outcome = outcome
    }

    public func setOutcome(_ outcome: Outcome) {
        self.outcome = outcome
    }

    public func invalidateCache() async {
        invalidateCount += 1
    }

    public func fetch() async throws -> UsageSnapshot {
        fetchCount += 1
        switch outcome {
        case .success(let snapshot): return snapshot
        case .failure(let error): throw error
        }
    }
}
