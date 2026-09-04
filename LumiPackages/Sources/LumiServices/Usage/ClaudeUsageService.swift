import Foundation
import LumiKit

/// Claude kullanım servisi (design/05 §1 — karar 32 ile güncellendi).
///
/// **Birincil yol (Orca paritesi):** kullanıcının kendi OAuth access token'ıyla
/// `GET api.anthropic.com/api/oauth/usage`. Anlıktır, process spawn'ı yoktur ve
/// abonelik kotasından DÜŞMEZ — `claude -p "/usage"`'ın aksine.
///
/// **Yedek yol:** token okunamazsa, token reddedilirse (401/403) ya da endpoint
/// tanınmayan bir yanıt/4xx verirse eski `claude -p "/usage"` +
/// `UsageOutputParser` yolu.
///
/// **Yedeğe DÜŞÜLMEYEN hâller:** transport hatası, 429 ve 5xx. Bunlar geçicidir;
/// CLI yedeği abonelik kotasından düşer, geçici bir sunucu hatası yüzünden
/// kotadan yemek karar 32'ye aykırıdır. Bir kez (jitter'lı) yeniden denenir,
/// hâlâ hata varsa `LumiError.usageUnavailable` fırlatılır ve stderr'e loglanır
/// (design/05: "hiçbir hata sessizce yutulmaz").
///
/// I/O ağırlıklı, UI-yüzlü değil → `actor`. Hata tek tip `LumiError` (karar 5).
public actor ClaudeUsageService: UsageServicing {
    /// Asılı kalmaya karşı timeout (design/05 §2: macOS'ta `timeout` yok).
    static let cliTimeout: TimeInterval = 15
    static let apiTimeout: TimeInterval = 10

    /// Geçici hatada tek yeniden deneme öncesi bekleme; üzerine jitter eklenir
    /// (aynı anda uyanan istemcilerin endpoint'i aynı milisaniyede dövmemesi).
    public static let defaultRetryDelay: Duration = .milliseconds(300)
    static let retryJitterMilliseconds = 150

    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public nonisolated var provider: AgentProvider { .claude }

    private let binaryName: String
    private let session: URLSession
    private let retryDelay: Duration
    private let accessToken: @Sendable () async -> String?

    public init(
        binaryName: String = "claude",
        session: URLSession = .shared,
        retryDelay: Duration = ClaudeUsageService.defaultRetryDelay
    ) {
        self.binaryName = binaryName
        self.session = session
        self.retryDelay = retryDelay
        self.accessToken = { await ClaudeOAuthCredentials.readAccessToken() }
    }

    /// Test enjeksiyonu: token kaynağı (keychain/dosya) ikame edilebilir.
    init(
        binaryName: String,
        session: URLSession,
        retryDelay: Duration,
        accessToken: @escaping @Sendable () async -> String?
    ) {
        self.binaryName = binaryName
        self.session = session
        self.retryDelay = retryDelay
        self.accessToken = accessToken
    }

    public func fetch() async throws -> UsageSnapshot {
        switch await fetchViaOAuth() {
        case .success(let snapshot):
            return snapshot
        case .useCLI(let reason):
            log("OAuth yolu kullanılamadı (\(reason)) — CLI yedeğine düşülüyor")
            return try await fetchViaCLI()
        case .unavailable(let detail):
            throw LumiError.usageUnavailable(detail: detail)
        }
    }

    // MARK: - Birincil: OAuth endpoint

    /// OAuth yolunun üç sonucu. "CLI'a düş" ile "hata" bilinçli olarak ayrıdır:
    /// CLI yedeği kotadan düştüğü için yalnız token/biçim sorunlarında kullanılır.
    private enum OAuthOutcome {
        case success(UsageSnapshot)
        case useCLI(reason: String)
        case unavailable(detail: String)
    }

    /// Tek denemenin sonucu; `.retryable` geçici hatadır (transport, 429, 5xx).
    private enum AttemptResult {
        case success(UsageSnapshot)
        case useCLI(reason: String)
        case retryable(detail: String)
    }

    private func fetchViaOAuth() async -> OAuthOutcome {
        guard let token = await accessToken() else {
            return .useCLI(reason: "OAuth token not found")
        }
        let request = Self.makeRequest(token: token)

        var lastDetail = "unknown error"
        for attempt in 0 ... 1 {
            if attempt > 0 {
                let delay = jitteredRetryDelay()
                if delay > .zero { try? await Task.sleep(for: delay) }
            }
            switch await performRequest(request) {
            case .success(let snapshot):
                return .success(snapshot)
            case .useCLI(let reason):
                return .useCLI(reason: reason)
            case .retryable(let detail):
                lastDetail = detail
                log(attempt == 0
                    ? "usage endpoint hatası: \(detail) — bir kez yeniden denenecek"
                    : "usage endpoint hatası sürüyor: \(detail)")
            }
        }
        return .unavailable(detail: lastDetail)
    }

    private func performRequest(_ request: URLRequest) async -> AttemptResult {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .retryable(detail: "transport error: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            return .retryable(detail: "non-HTTP response")
        }

        switch http.statusCode {
        case 200 ..< 300:
            guard let snapshot = ClaudeUsageAPIParser.parse(data) else {
                // Endpoint biçimi değişmiş olabilir; CLI hâlâ doğru cevabı verir.
                return .useCLI(reason: "usage response format not recognized")
            }
            return .success(snapshot)
        case 429, 500 ..< 600:
            return .retryable(detail: "HTTP \(http.statusCode)")
        default:
            // 401/403 token geçersiz, diğer 4xx endpoint değişikliği: yeniden
            // denemek düzeltmez, CLI yedeği devreye girer.
            return .useCLI(reason: "HTTP \(http.statusCode)")
        }
    }

    private static func makeRequest(token: String) -> URLRequest {
        var request = URLRequest(url: usageURL)
        request.timeoutInterval = apiTimeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Claude Code'un kendi çağrısıyla aynı beta başlığı; olmadan endpoint 4xx döner.
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func jitteredRetryDelay() -> Duration {
        guard retryDelay > .zero else { return .zero }
        return retryDelay + .milliseconds(Int.random(in: 0 ... Self.retryJitterMilliseconds))
    }

    /// Sessiz yutma yasak (design/05): her başarısız yol iz bırakır. Token
    /// hiçbir koşulda loglanmaz.
    private func log(_ message: String) {
        fputs("[lumi-usage] claude: \(message)\n", stderr)
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
