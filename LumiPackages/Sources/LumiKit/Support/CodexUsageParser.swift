import Foundation

/// `account/rateLimits/read` sonucunu `UsageSnapshot`'a çevirir (Orca paritesi —
/// `codex-rate-limit-window-classification.ts` + `codex-rate-limit-window-mapper.ts`).
/// Saf fonksiyon: process/ağ yok, tamamı test edilebilir.
///
/// Sunucu iki pencere döner: `primary` ve `secondary`. Hangisinin 5 saatlik
/// oturum, hangisinin haftalık olduğu SIRAYA göre değil `windowDurationMins`'e
/// göre belirlenir — süre tanınmazsa Orca'nın eski primary→session /
/// secondary→weekly eşlemesine düşülür.
public enum CodexUsageParser {
    public static let sessionWindowMinutes = 300
    public static let weeklyWindowMinutes = 10080
    /// Eski codex sürümlerinde görülen bir dakikalık sapmayı tolere eder,
    /// başka süreleri yutmaz.
    static let windowToleranceMinutes = 1

    /// `account/rateLimits/read` yanıtının ham JSON-RPC satırını çözer.
    /// Hiçbir pencere okunamazsa nil (çağıran `.usageUnavailable` fırlatır).
    public static func parse(responseLine data: Data, now: Date = Date()) -> UsageSnapshot? {
        guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = message["result"] as? [String: Any],
              let rateLimits = result["rateLimits"] as? [String: Any] else {
            return nil
        }
        return parse(rateLimits: rateLimits, now: now)
    }

    /// `rateLimits` nesnesini doğrudan alan varyant (testler + yeniden kullanım).
    static func parse(rateLimits: [String: Any], now: Date = Date()) -> UsageSnapshot? {
        let primary = window(from: rateLimits["primary"])
        let secondary = window(from: rateLimits["secondary"])
        let classified = classify(primary: primary, secondary: secondary)

        var limits: [UsageLimit] = []
        if let session = classified.session {
            limits.append(UsageLimit(kind: .session, rawLabel: "primary", window: session))
        }
        if let weekly = classified.weekly {
            limits.append(UsageLimit(kind: .weeklyAll, rawLabel: "secondary", window: weekly))
        }
        guard !limits.isEmpty else { return nil }
        return UsageSnapshot(limits: limits, mode: .subscription, fetchedAt: now)
    }

    // MARK: - Sınıflandırma

    private struct RawWindow {
        let window: UsageWindow
        let durationMinutes: Int?
    }

    private enum WindowKind {
        case session
        case weekly
    }

    private static func classify(
        primary: RawWindow?,
        secondary: RawWindow?
    ) -> (session: UsageWindow?, weekly: UsageWindow?) {
        var session: UsageWindow?
        var weekly: UsageWindow?
        for raw in [primary, secondary].compactMap({ $0 }) {
            switch kind(ofDuration: raw.durationMinutes) {
            case .session where session == nil: session = raw.window
            case .weekly where weekly == nil: weekly = raw.window
            default: break
            }
        }
        // Tanınmayan süreler: eski sıra tabanlı eşleme (Orca'nın legacy yolu).
        if session == nil, let primary, kind(ofDuration: primary.durationMinutes) == nil {
            session = primary.window
        }
        if weekly == nil, let secondary, kind(ofDuration: secondary.durationMinutes) == nil {
            weekly = secondary.window
        }
        return (session, weekly)
    }

    private static func kind(ofDuration minutes: Int?) -> WindowKind? {
        guard let minutes else { return nil }
        if abs(minutes - sessionWindowMinutes) <= windowToleranceMinutes { return .session }
        if abs(minutes - weeklyWindowMinutes) <= windowToleranceMinutes { return .weekly }
        return nil
    }

    // MARK: - Alan çevirileri

    private static func window(from value: Any?) -> RawWindow? {
        guard let entry = value as? [String: Any],
              let percent = intValue(entry["usedPercent"]) else {
            return nil
        }
        let date = resetDate(entry["resetsAt"])
        return RawWindow(
            window: UsageWindow(
                percentUsed: min(100, max(0, percent)),
                resetsAt: date,
                resetsRaw: date.map(UsageResetFormatter.string(from:)) ?? "",
                timezone: nil
            ),
            durationMinutes: intValue(entry["windowDurationMins"])
        )
    }

    /// Codex `resetsAt`'i Unix SANİYE olarak döner (Orca'nın notu; deneyle de
    /// doğrulandı). Milisaniye gelen bir sürüme karşı 1e10 eşiği korunur.
    static func resetDate(_ value: Any?) -> Date? {
        guard let seconds = doubleValue(value), seconds.isFinite, seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
    }

    private static func intValue(_ value: Any?) -> Int? {
        guard let number = doubleValue(value), number.isFinite else { return nil }
        return Int(number.rounded())
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let text = value as? String { return Double(text) }
        return nil
    }
}
