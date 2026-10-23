import Testing
import Foundation
import LumiKit
import LumiTestSupport
@testable import LumiRemote

extension FakeRelayConnection {
    func usageFrameCount() -> Int { sent.filter { $0.type == "usage" }.count }

    /// Son `usage` frame'indeki sağlayıcı kimlikleri + ilk limit yüzdesi + DeepSeek toplamı.
    func lastUsageSummary() -> (ids: [String], firstPercent: Int?, deepSeekTotal: String?)? {
        guard let payload = sent.last(where: { $0.type == "usage" })?.payload,
              let providers = payload["providers"] as? [[String: Any]] else { return nil }
        let limits = providers.first?["limits"] as? [[String: Any]]
        let deepSeek = payload["deepseek"] as? [String: Any]
        return (providers.compactMap { $0["id"] as? String },
                limits?.first?["percent"] as? Int,
                deepSeek?["total"] as? String)
    }
}

@Suite struct RemoteUsageReportTests {
    @Test func payloadCarriesLimitsResetAndDeepSeek() {
        let reset = Date(timeIntervalSince1970: 1_000)
        let snapshot = UsageSnapshot(limits: [
            UsageLimit(kind: .session, rawLabel: "Current session",
                       window: UsageWindow(percentUsed: 42, resetsAt: reset, resetsRaw: "", timezone: nil, duration: 18_000)),
            UsageLimit(kind: .weeklyModel("Opus"), rawLabel: "Current week (Opus)",
                       window: UsageWindow(percentUsed: nil, resetsAt: nil, resetsRaw: "", timezone: nil)),
        ], mode: .subscription, fetchedAt: reset)
        let balance = DeepSeekBalance(isAvailable: true, accounts: [
            .init(currency: "USD", total: Decimal(string: "12.34"), granted: nil, toppedUp: nil)
        ], fetchedAt: reset)
        let payload = RemoteUsageReport(
            providers: [.init(provider: .claude, snapshot: snapshot, errorMessage: nil),
                        .init(provider: .codex, snapshot: nil, errorMessage: "offline")],
            deepSeek: .init(balance: balance, errorMessage: nil)
        ).payload()

        let providers = payload["providers"] as? [[String: Any]]
        let limits = providers?[0]["limits"] as? [[String: Any]]
        #expect(limits?[0]["kind"] as? String == "session")
        #expect(limits?[0]["percent"] as? Int == 42)
        #expect(limits?[0]["resetsAt"] as? Double == 1_000_000)
        #expect(limits?[0]["durationSec"] as? Double == 18_000)
        #expect(limits?[0]["label"] as? String == "5-hour session", "readable title, not the raw provider label")
        #expect(limits?[1]["kind"] as? String == "model")
        #expect(limits?[1]["label"] as? String == "Weekly (Opus)")
        #expect(limits?[1]["percent"] == nil)
        #expect(providers?[1]["error"] as? String == "offline")
        let deepSeek = payload["deepseek"] as? [String: Any]
        #expect(deepSeek?["total"] as? String == "12.34")
        #expect(deepSeek?["currency"] as? String == "USD")
        #expect(deepSeek?["available"] as? Bool == true)
    }

    @Test func deepSeekKeyIsAbsentWhenIndicatorIsOff() {
        #expect(RemoteUsageReport(providers: [], deepSeek: nil).payload()["deepseek"] == nil)
    }
}

@Suite @MainActor struct RemoteServiceUsageTests {
    /// Rapor yayınlanır, aynısı tekrar gitmez, telefon bağlanınca (welcome) yeniden gönderilir.
    @Test func publishSendsOnceAndRepeatsOnWelcome() async throws {
        let conn = FakeRelayConnection()
        let cfg = FakeConfigService()
        await cfg.seed(AppConfig.defaults)
        let svc = RemoteService(
            paths: .testDefaults(), terminal: FakeTerminalServicing(), repos: FakeRepoService(repos: []),
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { AsyncStream { _ in } }, config: cfg
        )
        await svc.start()
        let report = RemoteUsageReport(providers: [.init(provider: .claude, snapshot: nil, errorMessage: nil)], deepSeek: nil)
        await svc.publishUsage(report)
        await svc.publishUsage(report)
        // Same content, new fetch time → still not resent.
        let refetched = RemoteUsageReport(providers: [.init(
            provider: .claude, snapshot: UsageSnapshot(limits: [], mode: .subscription, fetchedAt: Date()),
            errorMessage: nil)], deepSeek: nil)
        let refetchedLater = RemoteUsageReport(providers: [.init(
            provider: .claude, snapshot: UsageSnapshot(limits: [], mode: .subscription, fetchedAt: Date().addingTimeInterval(60)),
            errorMessage: nil)], deepSeek: nil)
        await svc.publishUsage(refetched)
        await svc.publishUsage(refetchedLater)
        try await conn.waitForCount(type: "usage", atLeast: 1)
        #expect(await conn.usageFrameCount() == 1)
        #expect(await conn.lastUsageSummary()?.ids == ["claude"])

        await conn.injectInbound(type: "welcome", payload: [:])
        try await conn.waitForCount(type: "usage", atLeast: 2)
        svc.stop()
    }
}
