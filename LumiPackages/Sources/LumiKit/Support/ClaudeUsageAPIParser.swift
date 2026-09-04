import Foundation

/// `GET api.anthropic.com/api/oauth/usage` gövdesini `UsageSnapshot`'a çevirir
/// (Orca paritesi — `claude-oauth-usage-request.ts` + `claude-usage-window.ts`).
/// Saf fonksiyon: ağ/process yok, tamamı test edilebilir (design/05 §parse).
///
/// Yanıttaki `limits` dizisi CLI'ın `/usage` çıktısıyla aynı değişken yapıdadır
/// (session + weekly_all + istediği kadar weekly_scoped), o yüzden `UsageSnapshot`
/// modeli iki kaynak için de olduğu gibi kullanılır — dizi SIRASI korunur.
public enum ClaudeUsageAPIParser {
    /// Gövde JSON'u tanınmazsa nil (çağıran `.usageUnavailable` fırlatır).
    public static func parse(_ data: Data, now: Date = Date()) -> UsageSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let limits = parseLimits(root["limits"]) ?? fallbackLimits(from: root)
        guard !limits.isEmpty else { return nil }
        return UsageSnapshot(limits: limits, mode: .subscription, fetchedAt: now)
    }

    // MARK: - `limits` dizisi (birincil biçim)

    private static func parseLimits(_ value: Any?) -> [UsageLimit]? {
        guard let array = value as? [[String: Any]] else { return nil }
        let limits = array.compactMap(limit(from:))
        return limits.isEmpty ? nil : limits
    }

    private static func limit(from entry: [String: Any]) -> UsageLimit? {
        guard let percent = JSONValue.roundedInt(entry["percent"], acceptingStrings: true) else { return nil }
        let kindRaw = (entry["kind"] as? String) ?? ""
        let modelName = scopedModelName(entry["scope"])
        let kind: UsageLimit.Kind
        switch kindRaw {
        case "session":
            kind = .session
        case "weekly_all":
            kind = .weeklyAll
        case "weekly_scoped":
            // Model adı yoksa satır düşürülmez: ham etiketiyle `.other` olarak taşınır.
            kind = modelName.map(UsageLimit.Kind.weeklyModel) ?? .other
        default:
            kind = .other
        }
        return UsageLimit(
            kind: kind,
            rawLabel: rawLabel(kindRaw: kindRaw, modelName: modelName),
            window: window(percent: percent, resetsAt: entry["resets_at"])
        )
    }

    private static func scopedModelName(_ scope: Any?) -> String? {
        guard let scope = scope as? [String: Any],
              let model = scope["model"] as? [String: Any],
              let name = (model["display_name"] as? String)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return nil
        }
        return name
    }

    private static func rawLabel(kindRaw: String, modelName: String?) -> String {
        if let modelName { return "Current week (\(modelName))" }
        return kindRaw.isEmpty ? "Limit" : kindRaw
    }

    // MARK: - Üst düzey alanlar (yedek biçim)

    /// `limits` gelmeyen/boş gelen yanıtlar için `five_hour` + `seven_day`.
    /// Orca da bu iki alanı ayrıca okur; burada yalnız yedek yoldur.
    private static func fallbackLimits(from root: [String: Any]) -> [UsageLimit] {
        var limits: [UsageLimit] = []
        if let window = topLevelWindow(root["five_hour"]) {
            limits.append(UsageLimit(kind: .session, rawLabel: "five_hour", window: window))
        }
        if let window = topLevelWindow(root["seven_day"]) {
            limits.append(UsageLimit(kind: .weeklyAll, rawLabel: "seven_day", window: window))
        }
        return limits
    }

    private static func topLevelWindow(_ value: Any?) -> UsageWindow? {
        guard let entry = value as? [String: Any] else { return nil }
        guard let percent = JSONValue.roundedInt(entry["utilization"], acceptingStrings: true)
            ?? JSONValue.roundedInt(entry["used_percentage"], acceptingStrings: true)
        else { return nil }
        return window(percent: percent, resetsAt: entry["resets_at"])
    }

    // MARK: - Ortak alan çevirileri

    private static func window(percent: Int, resetsAt: Any?) -> UsageWindow {
        let date = resetDate(resetsAt)
        return UsageWindow(
            percentUsed: min(100, max(0, percent)),
            resetsAt: date,
            resetsRaw: date.map(UsageResetFormatter.string(from:)) ?? "",
            timezone: nil
        )
    }

    /// ISO-8601 metin ya da epoch (saniye/milisaniye). Orca'nın eşiği: 1e10'un
    /// üstü milisaniye, altı saniye — 2286'ya kadar saniye epoch'larıyla çakışmaz.
    static func resetDate(_ value: Any?) -> Date? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let number = Double(trimmed) { return date(fromEpoch: number) }
            return parseISO8601(trimmed)
        }
        guard let number = JSONValue.double(value) else { return nil }
        return date(fromEpoch: number)
    }

    private static func date(fromEpoch value: Double) -> Date? {
        guard value.isFinite, value > 0 else { return nil }
        let seconds = value > 10_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }

    // MARK: - Formatter'lar

    /// Formatter'lar çağrı başına kurulur: `DateFormatter`/`ISO8601DateFormatter`
    /// Sendable değildir ve static let olarak Swift 6 strict concurrency'de
    /// geçmez (UsageOutputParser da aynı deseni kullanır). Parse dakikada bir
    /// koştuğu için maliyeti önemsizdir.
    private static func parseISO8601(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}
