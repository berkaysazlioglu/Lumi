import Foundation

/// Demo quota indicators (Mac decision 128): Claude on pace, Codex ahead of
/// pace, DeepSeek with a USD balance.
enum DemoUsage {
    private static let hourMs: Double = 3_600_000
    private static let fiveHoursSec: Double = 18_000
    private static let weekSec: Double = 604_800

    static func report(nowMs: Double) -> UsageReport {
        UsageReport(
            providers: [
                UsageProviderReport(id: "claude", limits: [
                    UsageLimitReport(id: "session", label: "Current session", kind: "session", percent: 38,
                                     resetsAt: nowMs + 3 * hourMs, durationSec: fiveHoursSec),
                    UsageLimitReport(id: "week.all", label: "Current week (all models)", kind: "week", percent: 21,
                                     resetsAt: nowMs + 120 * hourMs, durationSec: weekSec),
                    UsageLimitReport(id: "week.opus", label: "Current week (Opus)", kind: "model", percent: 64,
                                     resetsAt: nowMs + 120 * hourMs, durationSec: weekSec),
                ]),
                UsageProviderReport(id: "codex", limits: [
                    UsageLimitReport(id: "session", label: "5h limit", kind: "session", percent: 72,
                                     resetsAt: nowMs + 4 * hourMs, durationSec: fiveHoursSec),
                    UsageLimitReport(id: "week.all", label: "Weekly limit", kind: "week", percent: 33,
                                     resetsAt: nowMs + 90 * hourMs, durationSec: weekSec),
                ]),
            ],
            deepSeek: DeepSeekReport(available: true, currency: "USD", total: "12.40")
        )
    }
}
