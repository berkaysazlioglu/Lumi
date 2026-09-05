import AppKit
import Foundation
import Highlightr
import LumiKit

/// Vurgulayıcının görsel parametreleri (refactor 7.5).
///
/// `HighlightrEngine` LumiServices'te yaşadığı için `Theme`/`LumiFonts`'u
/// GÖREMEZ (katman kuralı). Palet ve font kararı composition root'tan enjekte
/// edilir; varsayılanlar tema kurulmadan da (test, araç) çalışır.
public struct HighlightrStyle: Sendable {
    /// highlight.js tema adı.
    public let themeName: String
    /// Vurgulanamayan (düz metin) içeriğin rengi.
    public let plainTextColor: NSColor
    /// Punto → monospace font çözümü.
    public let font: @Sendable (CGFloat) -> NSFont

    public init(
        themeName: String = "atom-one-dark",
        plainTextColor: NSColor = .textColor,
        font: @escaping @Sendable (CGFloat) -> NSFont = {
            .monospacedSystemFont(ofSize: $0, weight: .regular)
        }
    ) {
        self.themeName = themeName
        self.plainTextColor = plainTextColor
        self.font = font
    }
}

/// highlight.js (JSCore) tabanlı motor. Büyük dosyada düz metne düşer
/// (Highlightr'ın bilinen maliyeti — design/03 §6 cutoff).
public final class HighlightrEngine: SyntaxHighlighting {
    public static let plainTextCutoffBytes = 1_000_000

    private let style: HighlightrStyle
    private let queue = DispatchQueue(label: "lumi.highlightr", qos: .userInitiated)
    // Queue-confined: JSCore context'i bir kez kurulur, çağrılar arası yaşar
    nonisolated(unsafe) private var cachedHighlightr: Highlightr?

    public init(style: HighlightrStyle = HighlightrStyle()) {
        self.style = style
    }

    public func highlight(
        code: String,
        fileName: String,
        fontSize: CGFloat
    ) async -> NSAttributedString {
        let language = Self.language(forFileName: fileName)
        guard let language, code.utf8.count <= Self.plainTextCutoffBytes else {
            return plainText(code, fontSize: fontSize)
        }

        // NSAttributedString Sendable değil; queue→continuation geçişi kutuyla yapılır
        struct AttributedBox: @unchecked Sendable {
            let value: NSAttributedString?
        }
        let style = style
        let box: AttributedBox = await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                let highlightr: Highlightr?
                if let cached = self?.cachedHighlightr {
                    highlightr = cached
                } else {
                    highlightr = Highlightr()
                    highlightr?.setTheme(to: style.themeName)
                    self?.cachedHighlightr = highlightr
                }
                highlightr?.theme.codeFont = style.font(fontSize)
                continuation.resume(returning: AttributedBox(
                    value: highlightr?.highlight(code, as: language)
                ))
            }
        }
        return box.value ?? plainText(code, fontSize: fontSize)
    }

    func plainText(_ code: String, fontSize: CGFloat) -> NSAttributedString {
        NSAttributedString(string: code, attributes: [
            .font: style.font(fontSize),
            .foregroundColor: style.plainTextColor,
        ])
    }

    /// Uzantı → highlight.js dili (FileViewer dil haritası).
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
