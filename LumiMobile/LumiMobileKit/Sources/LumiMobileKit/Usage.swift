import Foundation

/// Mac top bar quota indicators mirrored to the phone (Mac decision 128):
/// only the indicators enabled on the Mac are present.
public struct UsageReport: Decodable, Sendable, Equatable {
    public let providers: [UsageProviderReport]
    /// `nil` when the DeepSeek indicator is off on the Mac.
    public let deepSeek: DeepSeekReport?

    public init(providers: [UsageProviderReport], deepSeek: DeepSeekReport? = nil) {
        self.providers = providers
        self.deepSeek = deepSeek
    }

    private enum CodingKeys: String, CodingKey { case providers, deepSeek = "deepseek" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            providers: (try? c.decodeIfPresent([UsageProviderReport].self, forKey: .providers)) ?? [],
            deepSeek: try? c.decodeIfPresent(DeepSeekReport.self, forKey: .deepSeek)
        )
    }

    public var isEmpty: Bool { providers.isEmpty && deepSeek == nil }
}

public struct UsageProviderReport: Decodable, Sendable, Equatable, Identifiable {
    /// `claude` | `codex` (unknown ids tolerated).
    public let id: String
    public let limits: [UsageLimitReport]
    public let error: String?

    public init(id: String, limits: [UsageLimitReport], error: String? = nil) {
        self.id = id
        self.limits = limits
        self.error = error
    }

    private enum CodingKeys: String, CodingKey { case id, limits, error }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            limits: (try? c.decodeIfPresent([UsageLimitReport].self, forKey: .limits)) ?? [],
            error: try c.decodeIfPresent(String.self, forKey: .error)
        )
    }

    public var title: String {
        switch id {
        case "claude": "Claude"
        case "codex": "Codex"
        default: id.capitalized
        }
    }

    /// The Mac top bar's source: the session window if present, else the first
    /// reported limit (Mac `UsageSnapshot.indicatorLimit`, decision 76).
    public var indicatorLimit: UsageLimitReport? {
        limits.first { $0.kind == "session" } ?? limits.first
    }
}

public struct UsageLimitReport: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    /// `session` | `week` | `model` | `other`.
    public let kind: String
    public let percent: Int?
    /// Epoch milliseconds.
    public let resetsAt: Double?
    /// Window length in seconds — only when the provider reports it.
    public let durationSec: Double?

    public init(id: String, label: String, kind: String, percent: Int?,
                resetsAt: Double? = nil, durationSec: Double? = nil) {
        self.id = id; self.label = label; self.kind = kind
        self.percent = percent; self.resetsAt = resetsAt; self.durationSec = durationSec
    }

    private enum CodingKeys: String, CodingKey { case id, label, kind, percent, resetsAt, durationSec }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        self.init(
            id: try c.decodeIfPresent(String.self, forKey: .id) ?? label,
            label: label,
            kind: try c.decodeIfPresent(String.self, forKey: .kind) ?? "other",
            percent: try c.decodeIfPresent(Int.self, forKey: .percent),
            resetsAt: try c.decodeIfPresent(Double.self, forKey: .resetsAt),
            durationSec: try c.decodeIfPresent(Double.self, forKey: .durationSec)
        )
    }

    /// Elapsed part of the window (0–1) when both reset time and length are known.
    public func elapsedFraction(nowMs: Double) -> Double? {
        guard let resetsAt, let durationSec, durationSec > 0 else { return nil }
        let elapsed = durationSec - (resetsAt - nowMs) / 1000
        return min(1, max(0, elapsed / durationSec))
    }
}

public struct DeepSeekReport: Decodable, Sendable, Equatable {
    public let available: Bool?
    public let currency: String?
    /// Decimal string as sent by the Mac (`"12.34"`).
    public let total: String?
    public let error: String?

    public init(available: Bool?, currency: String?, total: String?, error: String? = nil) {
        self.available = available; self.currency = currency; self.total = total; self.error = error
    }

    /// `$12.34` / `¥80.00` / `—`.
    public var balanceLabel: String {
        guard let total, let value = Double(total) else { return "—" }
        let symbol = currency == "CNY" ? "¥" : (currency == "USD" || currency == nil ? "$" : "\(currency!) ")
        return symbol + String(format: "%.2f", value)
    }
}

/// Where usage sits against the window's elapsed time (Mac `UsagePace`,
/// decision 85): -1 far behind (ice) … 0 on pace (green) … +1 critical (red).
public enum UsageTone: Sendable, Equatable {
    /// Ramp position; `nil` falls back to the absolute band.
    case pace(Double)
    /// No pace known: 0–49 normal, 50–79 warning, 80+ critical.
    case level(Int)
    case unknown

    public static let tolerance = 5
    public static let coolSpan = 25
    public static let warmSpan = 40
    public static let warningThreshold = 50
    public static let criticalThreshold = 80

    public init(limit: UsageLimitReport?, nowMs: Double) {
        guard let limit, let percent = limit.percent else { self = .unknown; return }
        guard let elapsed = limit.elapsedFraction(nowMs: nowMs) else { self = .level(percent); return }
        self = .pace(Self.stop(percent: percent, elapsedPoints: Int((elapsed * 100).rounded())))
    }

    static func stop(percent: Int, elapsedPoints: Int) -> Double {
        guard percent < 100 else { return 1 }
        let delta = percent - elapsedPoints
        let distance = abs(delta) - tolerance
        guard distance > 0 else { return 0 }
        let stop = min(1, Double(distance) / Double(delta > 0 ? warmSpan : coolSpan))
        return delta > 0 ? stop : -stop
    }
}

/// Short reset label: `in 2h 14m` / `in 3d 4h` / `now`.
public func usageResetLabel(_ resetsAtMs: Double?, nowMs: Double) -> String? {
    guard let resetsAtMs else { return nil }
    let minutes = Int(((resetsAtMs - nowMs) / 60_000).rounded())
    guard minutes > 0 else { return "now" }
    let days = minutes / 1440, hours = (minutes % 1440) / 60, mins = minutes % 60
    if days > 0 { return "in \(days)d \(hours)h" }
    if hours > 0 { return "in \(hours)h \(mins)m" }
    return "in \(mins)m"
}
