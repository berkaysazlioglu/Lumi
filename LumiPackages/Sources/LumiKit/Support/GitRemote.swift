import Foundation

/// `git remote get-url origin` çıktısının SAF normalizasyonu.
///
/// Yalnız GitHub desteklenir (karar 40): "Open on GitHub" ve "Create PR"
/// eylemlerinin ikisi de GitHub'a özgü. Başka host'ta nil döner ve eylemler
/// görünmez — yanlış bir URL üretmek sessiz bir hata olurdu.
public enum GitRemote {
    private static let gitHubHost = "github.com"

    /// `owner/repo` — `gh --repo` argümanı ve web URL'i bundan türer.
    public static func gitHubSlug(from remote: String) -> String? {
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let path: String
        if let scpPath = scpStylePath(trimmed) {
            path = scpPath
        } else if let url = URL(string: trimmed),
                  url.host?.lowercased().hasSuffix(gitHubHost) == true {
            path = url.path
        } else {
            return nil
        }

        let segments = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard segments.count >= 2 else { return nil }
        let owner = segments[segments.count - 2]
        var repo = segments[segments.count - 1]
        if repo.hasSuffix(".git") { repo = String(repo.dropLast(4)) }
        guard !owner.isEmpty, !repo.isEmpty else { return nil }
        return "\(owner)/\(repo)"
    }

    /// Repo'nun web adresi: `https://github.com/owner/repo`.
    public static func webURL(from remote: String) -> URL? {
        guard let slug = gitHubSlug(from: remote) else { return nil }
        return URL(string: "https://\(gitHubHost)/\(slug)")
    }

    /// Tek commit'in web adresi.
    public static func commitURL(from remote: String, sha: String) -> URL? {
        let cleanSHA = sha.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSHA.isEmpty, let base = webURL(from: remote) else { return nil }
        return base.appendingPathComponent("commit").appendingPathComponent(cleanSHA)
    }

    public static func isGitHub(_ remote: String) -> Bool {
        gitHubSlug(from: remote) != nil
    }

    /// `git@github.com:owner/repo.git` biçimi — URL değildir, elle ayrıştırılır.
    private static func scpStylePath(_ remote: String) -> String? {
        guard !remote.contains("://"), let colon = remote.firstIndex(of: ":") else { return nil }
        let hostPart = remote[remote.startIndex ..< colon]
        let host = hostPart.split(separator: "@").last.map(String.init) ?? String(hostPart)
        guard host.lowercased().hasSuffix(gitHubHost) else { return nil }
        return String(remote[remote.index(after: colon)...])
    }
}
