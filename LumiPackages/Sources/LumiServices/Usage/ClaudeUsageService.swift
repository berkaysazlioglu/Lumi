import Foundation
import LumiKit

/// Claude kullanım servisi (design/05 §1 — karar 32 ile güncellendi).
///
/// **Birincil yol (Orca paritesi):** kullanıcının kendi OAuth access token'ıyla
/// `GET api.anthropic.com/api/oauth/usage`. Anlıktır, process spawn'ı yoktur ve
/// abonelik kotasından DÜŞMEZ — `claude -p "/usage"`'ın aksine.
///
/// **Yedek yol:** token okunamazsa ya da istek başarısız olursa eski
/// `claude -p "/usage"` + `UsageOutputParser` yolu. Böylece keychain'e
/// erişilemeyen ya da endpoint'i değişen kurulumlarda gösterge kararmaz.
///
/// I/O ağırlıklı, UI-yüzlü değil → `actor`. Hata tek tip `LumiError` (karar 5).
public actor ClaudeUsageService: UsageServicing {
    /// Asılı kalmaya karşı timeout (design/05 §2: macOS'ta `timeout` yok).
    static let cliTimeout: TimeInterval = 15
    static let apiTimeout: TimeInterval = 10

    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public nonisolated var provider: AgentProvider { .claude }

    private let binaryName: String
    private let session: URLSession

    public init(binaryName: String = "claude", session: URLSession = .shared) {
        self.binaryName = binaryName
        self.session = session
    }

    public func fetch() async throws -> UsageSnapshot {
        if let snapshot = await fetchViaOAuth() { return snapshot }
        return try await fetchViaCLI()
    }

    // MARK: - Birincil: OAuth endpoint

    /// Başarısızlıkta nil döner (fırlatmaz): her başarısızlık CLI yoluna düşme
    /// sebebidir, kullanıcıya dönük hata CLI de başarısız olursa üretilir.
    private func fetchViaOAuth() async -> UsageSnapshot? {
        guard let token = await ClaudeOAuthCredentials.readAccessToken() else { return nil }

        var request = URLRequest(url: Self.usageURL)
        request.timeoutInterval = Self.apiTimeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Claude Code'un kendi çağrısıyla aynı beta başlığı; olmadan endpoint 4xx döner.
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode) else {
            return nil
        }
        return ClaudeUsageAPIParser.parse(data)
    }

    // MARK: - Yedek: `claude -p "/usage"`

    private func fetchViaCLI() async throws -> UsageSnapshot {
        guard let binary = await BinaryLocator.locate(binaryName) else {
            throw LumiError.cliNotFound(binary: binaryName)
        }

        guard let output = await ProcessRunner.run(
            binary, arguments: ["-p", "/usage"], timeout: Self.cliTimeout
        ) else {
            throw LumiError.usageUnavailable(
                detail: "\(binaryName) -p /usage timed out or failed to launch"
            )
        }

        guard output.exitCode == 0 else {
            let stderr = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LumiError.usageUnavailable(
                detail: stderr.isEmpty ? "exit code \(output.exitCode)" : stderr
            )
        }

        guard !output.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LumiError.usageUnavailable(detail: "empty output")
        }

        let snapshot = UsageOutputParser.parse(output.stdout)
        // mod tanınamadı VE hiçbir pencere yoksa → biçim tanınmadı (design/05).
        if snapshot.mode == .unknown, !snapshot.hasAnyWindow {
            throw LumiError.usageUnavailable(detail: "output format not recognized")
        }
        return snapshot
    }
}
