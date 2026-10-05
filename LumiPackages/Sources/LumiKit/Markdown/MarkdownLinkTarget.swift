import Foundation

/// Karar 109: render'lı markdown'da tıklanan link'in nereye gideceği.
///
/// GitHub'daki gibi göreli link (`docs/setup.md`, `../README.md#kurulum`)
/// açık dosyanın klasörüne göre çözülür ve aynı FileViewer'da açılır;
/// şemalı link (`https:`, `mailto:`) sisteme bırakılır. Repo kökünün dışına
/// taşan göreli yol reddedilir (karar 11 path-traversal sınırı).
public enum MarkdownLinkTarget: Equatable, Sendable {
    case external(URL)
    /// Repo köküne göre göreli yol (anchor atılmış).
    case file(String)
    /// Yalnız `#bölüm` — bu sürümde kaydırma yok, tık yutulur.
    case anchor
    case invalid

    public static func resolve(_ url: URL, from filePath: String) -> MarkdownLinkTarget {
        if let scheme = url.scheme, !scheme.isEmpty {
            // `file:` mutlak yolu da sisteme gider (Finder/varsayılan uygulama).
            return .external(url)
        }
        let raw = url.absoluteString
        let withoutAnchor = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard !withoutAnchor.isEmpty else { return .anchor }
        let decoded = withoutAnchor.removingPercentEncoding ?? withoutAnchor

        let base: [Substring] = decoded.hasPrefix("/")
            ? []
            : filePath.split(separator: "/").dropLast()
        var components: [Substring] = Array(base)
        for part in decoded.split(separator: "/") {
            switch part {
            case ".": continue
            case "..":
                guard !components.isEmpty else { return .invalid }
                components.removeLast()
            default:
                components.append(part)
            }
        }
        return components.isEmpty ? .invalid : .file(components.joined(separator: "/"))
    }
}

/// Fence dil etiketi → vurgulayıcının uzantı haritasına giden sahte dosya adı
/// (`SyntaxHighlighting` dili dosya adından çözer).
public enum MarkdownCodeLanguage {
    private static let aliases: [String: String] = [
        "csharp": "cs", "c#": "cs",
        "javascript": "js", "typescript": "ts",
        "python": "py", "rust": "rs", "kotlin": "kt", "ruby": "rb",
        "shell": "sh", "console": "sh", "zsh": "sh", "bash": "sh",
        "c++": "cpp", "objective-c": "h",
        "yml": "yaml", "jsonc": "json", "html": "html", "markdown": "md",
    ]

    public static func fileName(for language: String?) -> String? {
        guard let language = language?.lowercased(), !language.isEmpty else { return nil }
        return "snippet.\(aliases[language] ?? language)"
    }
}
