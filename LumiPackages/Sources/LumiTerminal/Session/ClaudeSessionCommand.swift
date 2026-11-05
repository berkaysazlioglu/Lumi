import Foundation
import LumiKit

/// Karar 23: claude launch komutuna oturum kimliği enjeksiyonu/çıkarımı.
///
/// Oturum ID'si SPAWN ANINDA belirlenir (`--session-id`) — çıktı scraping
/// yapılmaz: terminal içeriğinde geçen herhangi bir `claude --resume ...`
/// metni yanlış pozitif üretirdi; ID'yi baştan bilmek kill-güvenli ve
/// çoklu-terminal-güvenlidir (ampirik doğrulama karar 23'te).
public enum ClaudeSessionCommand {
    private static let uuidPattern =
        "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"

    /// ID taşıyan flag'ler: değeri komuttan geri okunabilir.
    private static let idCarryingFlags = ["--session-id", "--resume", "-r"]
    /// Oturum belirleyen ama ID'si bilinemeyen flag'ler (CWD'den seçer).
    private static let sessionSelectingFlags = ["--continue", "-c"]

    /// Spawn komutunu hazırlar:
    /// - ilk token `claude` değilse komut aynen geçer (sessionID nil);
    /// - komutta ID'li oturum flag'i varsa komut değişmez, ID çıkarılır;
    /// - `-c/--continue` varsa komut değişmez, ID bilinemez (nil);
    /// - aksi halde `--session-id <uuid>` eklenir ve ID döner.
    public static func prepare(
        command: String?,
        generateID: () -> String = { UUID().uuidString.lowercased() }
    ) -> (command: String?, sessionID: String?) {
        guard let command else { return (nil, nil) }
        guard firstToken(of: command) == "claude" else { return (command, nil) }
        if let existing = extractSessionID(from: command) {
            return (command, existing)
        }
        if hasFlag(command, anyOf: idCarryingFlags + sessionSelectingFlags) {
            return (command, nil)
        }
        let id = generateID()
        return ("\(command) --session-id \(id)", id)
    }

    /// Karar 140: kimliği spawn'da bilinmeyen terminal, içinde koşan claude'un
    /// kimliğini lider hook'tan öğrenebilir mi. Hayır yalnız claude'un
    /// sarmalanarak açıldığı launch'ta (`source deepseek.env && claude`):
    /// resume düz `claude --resume` olurdu ve DeepSeek yerine aboneliğe
    /// geçerdi (karar 54). Düz shell, `-c/--continue` ve başka ajanlar öğrenir.
    public static func allowsAdoptingSession(launchCommand: String?) -> Bool {
        guard let launchCommand, firstToken(of: launchCommand) != "claude" else { return true }
        return AgentProvider.detect(launchCommand: launchCommand) != .claude
    }

    /// Restore spawn komutu: resume dener; oturum yoksa claude exit 1 verir
    /// (ampirik) ve AYNI kimlikle taze claude'a düşülür (`--session-id`).
    /// Hiç mesaj almamış oturumun transcript'i yazılmamış olur; eskiden düşüş
    /// kimliksiz `claude`'du — claude rastgele bir kimlikle başlıyor, terminal
    /// ise eski kimliği tutuyordu: chat köprüsü (telefon, Mac controller)
    /// olmayan transcript'i izleyip hiçbir cevabı göstermiyordu. Kimlik zaten
    /// kullanımdaysa (resume edilen claude sıfırdan farklı kodla çıktı) son
    /// çare kimliksiz claude'dur.
    /// Karar 141: `arguments` koşan claude'dan okunan bayraklardır; kayıt
    /// dosyadan geldiği için beyaz listeden yeniden geçer ve her biri tırnaklanır.
    /// Taze claude'a düşüş de aynı bayraklarla açılır.
    public static func resumeCommand(sessionID: String, arguments: [String] = []) -> String {
        let flags = ClaudeLaunchArguments.filter(arguments).map { " " + quotedIfNeeded($0) }.joined()
        return "claude\(flags) --resume \(sessionID) || claude\(flags) --session-id \(sessionID) || claude\(flags)"
    }

    /// `--model opus` okunur kalsın: yalnız kabuğa özel karakter taşıyan
    /// argüman tek tırnaklanır.
    private static func quotedIfNeeded(_ argument: String) -> String {
        let plain = argument.range(of: #"^[A-Za-z0-9_./:=,@%+-]+$"#, options: .regularExpression) != nil
        return plain ? argument : shellQuoted(argument)
    }

    // MARK: - Private

    private static func firstToken(of command: String) -> String? {
        command.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }

    /// ID tırnaklı da gelebilir: Agent History'nin "Resume Session" eylemi
    /// kabuk güvenliği için `claude --resume '<id>'` üretir. Tırnağı kabul
    /// etmeyen desen bu komutta ID'yi kaçırıyor, terminal
    /// `claudeSessionID`'siz kalıyor ve çıkışta persist EDİLMİYORDU — yani
    /// resume edilen sohbet bir sonraki açılışta geri gelmiyordu.
    private static func extractSessionID(from command: String) -> String? {
        let flags = idCarryingFlags.map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        // \\1 geri referansı: açan ve kapayan tırnak aynı olmak zorunda.
        let pattern = "(?:^|\\s)(?:\(flags))\\s+([\'\"]?)(\(uuidPattern))\\1(?:\\s|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: command,
                  range: NSRange(command.startIndex..., in: command)
              ),
              let range = Range(match.range(at: 2), in: command) else {
            return nil
        }
        return String(command[range]).lowercased()
    }

    private static func hasFlag(_ command: String, anyOf flags: [String]) -> Bool {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        return tokens.contains { flags.contains($0) }
    }
}
