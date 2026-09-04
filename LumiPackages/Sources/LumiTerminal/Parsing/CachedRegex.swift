import Foundation

/// Sıcak yolda (her output chunk'ı, her tuş vuruşu) yeniden derlenmemesi için
/// önceden derlenmiş NSRegularExpression sarmalayıcısı.
///
/// `String.range(of:options:.regularExpression)` her çağrıda yeni bir regex
/// derler; parser ve inference yollarında bu ölçülebilir bir maliyettir.
/// Geçersiz pattern'de (derleme hatası) eşleşme üretmez — çağrı yerleri
/// sabit literal pattern kullandığı için bu yol pratikte ölüdür.
struct CachedRegex: Sendable {
    private let regex: NSRegularExpression?

    init(_ pattern: String, options: NSRegularExpression.Options = []) {
        self.regex = try? NSRegularExpression(pattern: pattern, options: options)
    }

    func matches(_ text: String) -> Bool {
        guard let regex else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}
