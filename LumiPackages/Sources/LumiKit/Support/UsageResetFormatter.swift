import Foundation

/// Reset zamanının ham metin gösterimi. CLI'ın `/usage` çıktısındaki biçimin
/// (`Jun 12 at 1:39pm`) aynısını üretir; böylece popover üç kaynağı da (CLI
/// parse, Claude OAuth, Codex RPC) tek satır biçiminde gösterir.
///
/// Formatter çağrı başına kurulur: `DateFormatter` Sendable değildir ve `static
/// let` olarak Swift 6 strict concurrency'de geçmez (`UsageOutputParser` de aynı
/// deseni kullanır). Parse dakikada bir koştuğu için maliyeti önemsizdir.
enum UsageResetFormatter {
    static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        formatter.dateFormat = "MMM d 'at' h:mma"
        return formatter.string(from: date)
    }
}
