import Foundation
import LumiKit

/// Son Lumi sürümünü GitHub Releases'ten okur (karar 102) —
/// `GET api.github.com/repos/<owner>/<repo>/releases/latest`.
///
/// Repo public olduğu için anahtar gerekmez. `latest` uç noktası draft ve
/// pre-release'leri zaten döndürmez: CI'ın açtığı draft yayınlanana kadar
/// "yeni sürüm" görünmez. Yetkisiz istek sınırı saatte 60'tır; uygulama
/// açılışta bir kez + kullanıcı istedikçe sorar.
public actor GitHubReleaseService: AppReleaseChecking {
    public static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/berkaysazlioglu/Lumi/releases/latest"
    )!
    static let timeout: TimeInterval = 10

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func latestRelease() async throws -> AppRelease {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.timeoutInterval = Self.timeout
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LumiError.updateCheckFailed(detail: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw LumiError.updateCheckFailed(detail: "unexpected response")
        }
        guard http.statusCode == 200 else {
            throw LumiError.updateCheckFailed(detail: Self.detail(forStatus: http.statusCode))
        }
        guard let release = GitHubReleaseParser.parse(data) else {
            throw LumiError.updateCheckFailed(detail: "unrecognized response format")
        }
        return release
    }

    static func detail(forStatus code: Int) -> String {
        switch code {
        case 403, 429: return "HTTP \(code) — GitHub rate limit, try again later"
        case 404: return "HTTP 404 — no published release yet"
        case 500 ... 599: return "HTTP \(code) — GitHub server error"
        default: return "HTTP \(code)"
        }
    }
}

/// `releases/latest` yanıtının yalnız ihtiyaç duyulan alanları.
enum GitHubReleaseParser {
    static func parse(_ data: Data) -> AppRelease? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String,
              let version = AppVersion(tag),
              let page = (object["html_url"] as? String).flatMap(URL.init(string:))
        else { return nil }
        let publishedAt = (object["published_at"] as? String)
            .flatMap { ISO8601DateFormatter().date(from: $0) }
        return AppRelease(version: version, pageURL: page, publishedAt: publishedAt)
    }
}
