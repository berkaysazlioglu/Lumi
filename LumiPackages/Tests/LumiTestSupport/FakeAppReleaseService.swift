import Foundation
import LumiKit

/// `AppReleaseChecking` test ikamesi (karar 102): ağ yok, sonuç scriptlenir.
public actor FakeAppReleaseService: AppReleaseChecking {
    public enum Outcome: Sendable {
        case success(AppRelease)
        case failure(LumiError)
    }

    private var outcome: Outcome
    public private(set) var checkCount = 0

    public init(outcome: Outcome = .success(.fake())) {
        self.outcome = outcome
    }

    public func setOutcome(_ outcome: Outcome) {
        self.outcome = outcome
    }

    public func latestRelease() async throws -> AppRelease {
        checkCount += 1
        switch outcome {
        case .success(let release): return release
        case .failure(let error): throw error
        }
    }
}

public extension AppRelease {
    static func fake(version: String = "0.8.0") -> AppRelease {
        AppRelease(
            version: AppVersion(version)!,
            pageURL: URL(string: "https://github.com/berkaysazlioglu/Lumi/releases/tag/v\(version)")!,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}
