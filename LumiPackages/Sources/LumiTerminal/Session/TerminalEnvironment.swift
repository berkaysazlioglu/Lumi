import Foundation

/// PTY child'ına verilecek environment'ı üretir.
///
/// TERM ve COLORTERM her zaman Lumi'nin (SwiftTerm backend) yeteneklerini
/// deklare eder — miras alınan değerler DIŞ terminali (iTerm vb.) tanımlar ve
/// launch bağlamına göre değişir: Finder'dan açılan .app'te COLORTERM hiç
/// yoktur, `swift run`'da dış terminalden sızar. Bu fark, PTY'deki CLI'ların
/// (Claude Code dahil) truecolor yerine 256-renk paletine düşmesine ve
/// terminal renklerinin paketli build'de soluk görünmesine yol açıyordu.
enum TerminalEnvironment {
    static func childEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        if environment["LANG"] == nil {
            environment["LANG"] = "en_US.UTF-8"
        }
        return environment
    }
}
