import Foundation
import LumiKit

/// UsageServicing test ikamesi (design/00 §3 deseni). Sonuç kontrol edilebilir;
/// fetch çağrı sayısı izlenir (min-interval / load-once doğrulaması için).
actor FakeUsageService: UsageServicing {
    enum Outcome: Sendable {
        case success(UsageSnapshot)
        case failure(LumiError)
    }

    private var outcome: Outcome
    private(set) var fetchCount = 0

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func setOutcome(_ outcome: Outcome) {
        self.outcome = outcome
    }

    func fetch() async throws -> UsageSnapshot {
        fetchCount += 1
        switch outcome {
        case .success(let snapshot): return snapshot
        case .failure(let error): throw error
        }
    }
}
