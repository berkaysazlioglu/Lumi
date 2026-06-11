import AppKit
import Foundation
import Highlightr

/// Sözdizimi vurgulama dikişi (design/03 §6): FileViewer yalnız bu protokole
/// bağlanır — Highlightr yetersiz kalırsa tree-sitter'a view'a dokunmadan geçilir.
@MainActor
public protocol SyntaxHighlighting: AnyObject {
    func highlight(code: String, fileName: String, fontSize: CGFloat) async -> NSAttributedString
}

/// highlight.js (JSCore) tabanlı motor. Büyük dosyada düz metne düşer
/// (Highlightr'ın bilinen maliyeti — design/03 §6 cutoff).
public final class HighlightrEngine: SyntaxHighlighting {
    public static let plainTextCutoffBytes = 1_000_000

    private let queue = DispatchQueue(label: "lumi.highlightr", qos: .userInitiated)
    // Queue-confined: JSCore context'i bir kez kurulur, çağrılar arası yaşar
    nonisolated(unsafe) private var cachedHighlightr: Highlightr?

    public init() {}

    public func highlight(
        code: String,
        fileName: String,
        fontSize: CGFloat
    ) async -> NSAttributedString {
        let language = Self.language(forFileName: fileName)
        guard let language, code.utf8.count <= Self.plainTextCutoffBytes else {
            return Self.plainText(code, fontSize: fontSize)
        }

        // NSAttributedString Sendable değil; queue→continuation geçişi kutuyla yapılır
        struct AttributedBox: @unchecked Sendable {
            let value: NSAttributedString?
        }
        let box: AttributedBox = await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                let highlightr: Highlightr?
                if let cached = self?.cachedHighlightr {
                    highlightr = cached
                } else {
                    highlightr = Highlightr()
                    highlightr?.setTheme(to: "atom-one-dark")
                    self?.cachedHighlightr = highlightr
                }
                highlightr?.theme.codeFont = LumiFonts.mono(size: fontSize)
                continuation.resume(returning: AttributedBox(
                    value: highlightr?.highlight(code, as: language)
                ))
            }
        }
        return box.value ?? Self.plainText(code, fontSize: fontSize)
    }

    static func plainText(_ code: String, fontSize: CGFloat) -> NSAttributedString {
        NSAttributedString(string: code, attributes: [
            .font: LumiFonts.mono(size: fontSize),
            .foregroundColor: Theme.NS.textPrimary,
        ])
    }

    /// Uzantı → highlight.js dili (spec/22 FileViewer dil haritası).
    static func language(forFileName fileName: String) -> String? {
        let name = (fileName as NSString).lastPathComponent.lowercased()
        if name == "dockerfile" { return "dockerfile" }
        let ext = (name as NSString).pathExtension
        switch ext {
        case "ts", "tsx": return "typescript"
        case "js", "jsx", "mjs", "cjs": return "javascript"
        case "json": return "json"
        case "md", "markdown": return "markdown"
        case "css": return "css"
        case "scss": return "scss"
        case "html", "htm": return "xml"
        case "py": return "python"
        case "rs": return "rust"
        case "go": return "go"
        case "yaml", "yml": return "yaml"
        case "sh", "bash", "zsh": return "bash"
        case "toml", "ini": return "ini"
        case "sql": return "sql"
        case "xml", "svg": return "xml"
        case "graphql", "gql": return "graphql"
        case "swift": return "swift"
        case "c", "h": return "c"
        case "cpp", "cc", "hpp": return "cpp"
        case "java": return "java"
        case "kt", "kts": return "kotlin"
        case "rb": return "ruby"
        case "cs": return "csharp"
        case "txt", "": return nil
        default: return nil
        }
    }
}
