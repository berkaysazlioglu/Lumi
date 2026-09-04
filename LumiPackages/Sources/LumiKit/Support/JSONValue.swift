import Foundation

/// `JSONSerialization` çıktısından (heterojen `Any`) lenient skalar okuma —
/// üç kopyanın (ConfigCodec, ClaudeUsageAPIParser, CodexUsageParser) tek tanımı
/// (refactor 5.7).
///
/// İki gerçek semantik fark parametre/isimle korunur:
/// 1. **Bool sızması engeli (her yerde geçerli):** `JSONSerialization` `true`/
///    `false` değerlerini de `NSNumber` üretir; `as? Int` bunları 1/0'a çevirir.
///    Sayı okuyucuları bool'u REDDEDER, bool okuyucusu yalnız bool kabul eder.
/// 2. **String kabulü (yalnız kullanım API'leri):** Claude/Codex uçları sayıyı
///    bazen `"42"` diye döner; config dosyasında böyle bir tolerans YOKTUR
///    (elle yazılmış `"13"` sessizce kabul edilirse format sözleşmesi bulanır).
///    Bu yüzden `acceptingStrings` çağrı yerinde açıkça seçilir.
///
/// Kesirli → tam sayı dönüşümünde de iki davranış vardır ve ikisi de isimlidir:
/// `int(_:)` KESER (config: `13.9 → 13`), `roundedInt(_:)` YUVARLAR (kullanım
/// yüzdeleri: `13.9 → 14`).
public enum JSONValue {
    /// Tam sayı; kesirli değer KESİLİR. Bool asla sayı sayılmaz.
    public static func int(_ value: Any?, acceptingStrings: Bool = false) -> Int? {
        if let number = numeric(value) { return number.intValue }
        guard acceptingStrings, let text = value as? String, let parsed = Double(text) else {
            return nil
        }
        return parsed.isFinite ? Int(parsed) : nil
    }

    /// Tam sayı; kesirli değer YUVARLANIR (kullanım yüzdesi/limit alanları).
    public static func roundedInt(_ value: Any?, acceptingStrings: Bool = false) -> Int? {
        guard let number = double(value, acceptingStrings: acceptingStrings), number.isFinite else {
            return nil
        }
        return Int(number.rounded())
    }

    /// Ondalık sayı. Bool asla sayı sayılmaz.
    public static func double(_ value: Any?, acceptingStrings: Bool = false) -> Double? {
        if let number = numeric(value) { return number.doubleValue }
        guard acceptingStrings, let text = value as? String else { return nil }
        return Double(text)
    }

    /// Yalnız gerçek bool (`true`/`false`); 1/0 sayısı bool sayılmaz.
    public static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, isBoolean(number) else { return nil }
        return number.boolValue
    }

    /// Bool olmayan `NSNumber` (Swift `Int`/`Double` de buraya köprülenir).
    private static func numeric(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber, !isBoolean(number) else { return nil }
        return number
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
