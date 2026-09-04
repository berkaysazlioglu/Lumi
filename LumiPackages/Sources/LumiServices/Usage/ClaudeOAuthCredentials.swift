import Foundation
import LumiKit

/// Claude Code'un kendi OAuth access token'ını okur (Orca paritesi —
/// `claude-oauth-credentials.ts`). Token kullanıcının KENDİ hesabına aittir ve
/// yalnız kendi kullanım verisini okumak için kullanılır; hiçbir yere yazılmaz,
/// loglanmaz, gösterilmez.
///
/// Kaynak sırası Orca'nınkiyle aynıdır:
/// 1. macOS Keychain — servis `Claude Code-credentials`, hesap `$USER`
///    (Claude Code 2.1+ burayı kullanır).
/// 2. `~/.claude/.credentials.json` — keychain'e yazamayan kurulumlar.
///
/// `expiresAt` bilinçli olarak DEĞERLENDİRİLMEZ: alan otoriter değil, süresi
/// dolmuş sayılan bir token'ı baştan elemek yerine sunucunun 401 dönmesine
/// bırakılır (Orca'nın gerekçesi birebir).
struct ClaudeOAuthCredentials: Sendable {
    /// Claude Code'un keychain servis adı.
    static let keychainService = "Claude Code-credentials"
    static let credentialsFileName = ".credentials.json"

    /// `security` çağrısı asılı kalmaya karşı — keychain kilitliyse UI'ı bekletmez.
    static let keychainTimeout: TimeInterval = 5

    private let runner: any ProcessRunning
    private let readFile: @Sendable (String) -> Data?

    init(
        runner: any ProcessRunning = SystemProcessRunner(),
        readFile: @escaping @Sendable (String) -> Data? = {
            FileManager.default.contents(atPath: $0)
        }
    ) {
        self.runner = runner
        self.readFile = readFile
    }

    /// Token bulunamazsa nil. Hata fırlatmaz: "token yok" bir arıza değil,
    /// CLI yoluna düşmek için normal bir durumdur.
    func readAccessToken(
        homeDirectory: String = NSHomeDirectory(),
        user: String = ProcessInfo.processInfo.environment["USER"] ?? "user"
    ) async -> String? {
        if let token = await readFromKeychain(user: user) { return token }
        return readFromFile(homeDirectory: homeDirectory)
    }

    // MARK: - Kaynaklar

    private func readFromKeychain(user: String) async -> String? {
        guard let result = await runner.run(
            "/usr/bin/security",
            arguments: ["find-generic-password", "-s", Self.keychainService, "-a", user, "-w"],
            timeout: Self.keychainTimeout
        ), result.exitCode == 0 else {
            return nil
        }
        return Self.accessToken(fromJSON: result.stdout)
    }

    private func readFromFile(homeDirectory: String) -> String? {
        let path = (homeDirectory as NSString)
            .appendingPathComponent(".claude/\(Self.credentialsFileName)")
        guard let data = readFile(path) else { return nil }
        return Self.accessToken(fromJSON: String(decoding: data, as: UTF8.self))
    }

    // MARK: - Parse (saf — test edilebilir)

    /// `{"claudeAiOauth":{"accessToken":"…"}}` → token. Biçim tanınmazsa nil.
    static func accessToken(fromJSON raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            return nil
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
