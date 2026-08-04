import Foundation

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

    /// Restore spawn komutu: resume dener; oturum yoksa claude exit 1 verir
    /// (ampirik) ve taze claude'a düşülür.
    public static func resumeCommand(sessionID: String) -> String {
        "claude --resume \(sessionID) || claude"
    }

    // MARK: - Private

    private static func firstToken(of command: String) -> String? {
        command.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }

    private static func extractSessionID(from command: String) -> String? {
        let flags = idCarryingFlags.map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let pattern = "(?:^|\\s)(?:\(flags))\\s+(\(uuidPattern))(?:\\s|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: command,
                  range: NSRange(command.startIndex..., in: command)
              ),
              let range = Range(match.range(at: 1), in: command) else {
            return nil
        }
        return String(command[range]).lowercased()
    }

    private static func hasFlag(_ command: String, anyOf flags: [String]) -> Bool {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        return tokens.contains { flags.contains($0) }
    }
}
