import Foundation

/// Custom kaynağın adres doğrulaması (plan: "Güvenlik").
///
/// Token her istekte gittiği için düz `http` yalnız bu makinedeki sunucuya
/// (loopback) izinlidir; geri kalan her adres `https` olmak zorundadır.
public enum TaskEndpoint {
    public enum Problem: Error, Equatable, Sendable {
        case empty
        case invalid
        case insecure

        public var message: String {
            switch self {
            case .empty: "Enter the server's address."
            case .invalid: "This doesn't look like a web address."
            case .insecure: "Use https:// — plain http is only allowed for localhost."
            }
        }
    }

    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    /// Baştaki/sondaki boşluk ve sondaki `/` atılır; şema yazılmamışsa
    /// `https://` varsayılır.
    public static func normalize(_ raw: String) -> Result<URL, Problem> {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.empty) }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty,
              let url = components.url
        else { return .failure(.invalid) }
        switch scheme {
        case "https": return .success(url)
        case "http": return loopbackHosts.contains(host) ? .success(url) : .failure(.insecure)
        default: return .failure(.invalid)
        }
    }
}
