import Foundation

/// `claude -p "/usage"` stdout'unu `UsageSnapshot`'a çeviren SAF fonksiyon
/// (design/05 §4). Process spawn'dan bağımsız → örnek çıktılarla unit-test edilir.
/// Dayanıklı: tam string eşleşmesine güvenmez (regex + içerir-kontrolü); eksik
/// satır / bozuk değer / API-key modu crash üretmez, yalnız o alanı boş bırakır.
public enum UsageOutputParser {
    /// - Parameters:
    ///   - raw: ham stdout.
    ///   - now: `fetchedAt` ve reset yılı için referans (test'te sabitlenir).
    public static func parse(_ raw: String, now: Date = Date()) -> UsageSnapshot {
        let mode = detectMode(raw)
        var fiveHour: UsageWindow?
        var weekAll: UsageWindow?
        var weekSonnet: UsageWindow?
        var weekOpus: UsageWindow?

        for rawLine in raw.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let label = line[..<colon].lowercased()
            let value = String(line[line.index(after: colon)...])
            guard let window = parseWindow(value, now: now) else { continue }

            // Sıra önemli: "session" → 5sa; "sonnet"/"opus" haftalık alt model;
            // niteleyicisiz "week" → tüm modeller.
            if label.contains("session") {
                fiveHour = window
            } else if label.contains("sonnet") {
                weekSonnet = window
            } else if label.contains("opus") {
                weekOpus = window
            } else if label.contains("week") {
                weekAll = window
            }
        }

        return UsageSnapshot(
            fiveHour: fiveHour,
            weekAll: weekAll,
            weekSonnet: weekSonnet,
            weekOpus: weekOpus,
            mode: mode,
            fetchedAt: now
        )
    }

    // MARK: - Mod

    private static func detectMode(_ raw: String) -> UsageSnapshot.Mode {
        let lower = raw.lowercased()
        if lower.contains("api key") { return .apiKey }
        if lower.contains("subscription") { return .subscription }
        return .unknown
    }

    // MARK: - Tek satır → pencere

    /// Değer kısmından yüzde + reset çıkarır. İkisi de yoksa nil (pencere değil).
    private static func parseWindow(_ value: String, now: Date) -> UsageWindow? {
        let percent = parsePercent(value)
        let reset = parseReset(value, now: now)
        if percent == nil, reset == nil { return nil }
        return UsageWindow(
            percentUsed: percent,
            resetsAt: reset?.date,
            resetsRaw: reset?.raw ?? "",
            timezone: reset?.timezone
        )
    }

    private static func parsePercent(_ value: String) -> Int? {
        guard let range = value.range(of: #"\d+%"#, options: .regularExpression) else { return nil }
        let digits = value[range].dropLast() // "%"
        guard let number = Int(digits) else { return nil }
        return min(100, max(0, number))
    }

    private struct ResetInfo {
        let raw: String
        let timezone: String?
        let date: Date?
    }

    /// `resets Jun 12 at 1:39pm (Europe/Istanbul)` → ham metin + tz + Date.
    private static func parseReset(_ value: String, now: Date) -> ResetInfo? {
        guard let resetsRange = value.range(of: #"(?i)resets\s+"#, options: .regularExpression) else {
            return nil
        }
        let after = String(value[resetsRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !after.isEmpty else { return nil }

        var raw = after
        var timezone: String?
        if let open = after.lastIndex(of: "("),
           let close = after.lastIndex(of: ")"),
           open < close {
            timezone = String(after[after.index(after: open)..<close])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            raw = String(after[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let zone = timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        let date = resolveDate(raw, timeZone: zone, now: now)
        return ResetInfo(raw: raw, timezone: timezone, date: date)
    }

    /// `MMM d 'at' h:mma` formatı; yıl yoktur → `now`'un yılı varsayılır.
    /// Sonuç bir günden fazla geçmişte görünürse yıl sınırı kabul edilip gelecek
    /// yıla taşınır (Aralık→Ocak devri). Parse başarısızsa nil (ham metin kalır).
    private static func resolveDate(_ raw: String, timeZone: TimeZone, now: Date) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        formatter.dateFormat = "MMM d 'at' h:mma"
        guard let base = formatter.date(from: raw) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let currentYear = calendar.component(.year, from: now)
        var components = calendar.dateComponents([.month, .day, .hour, .minute], from: base)
        components.year = currentYear
        guard var resolved = calendar.date(from: components) else { return nil }

        if resolved < now.addingTimeInterval(-86_400),
           let bumped = calendar.date(byAdding: .year, value: 1, to: resolved) {
            resolved = bumped
        }
        return resolved
    }
}
