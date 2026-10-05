import AppKit
import Foundation
import JavaScriptCore
import LumiKit

/// highlight.js (JavaScriptCore) tabanlı vurgulayıcı (karar 111).
///
/// Highlightr sarmalayıcısı bırakıldı: CSS tema okuyucusu iki parçalı
/// seçicileri okuyamıyordu (tip/fonksiyon/sınıf adları renksiz), JSContext'i
/// kapalıydı (Lumi gramerleri kaydedilemiyordu) ve bilinmeyen dilde tüm
/// dosyayı sessizce otomatik algılamaya sokuyordu. Motor aynı (highlight.js
/// 11.11.1, BSD-3 — `Resources/`'ta); üstüne `Resources/grammars/` altındaki
/// Lumi gramerleri (HLSL, ShaderLab, HCL) yüklenir, HTML çıktısını
/// `HighlightHTMLRenderer` boyar.
///
/// JSContext tek bir seri kuyruğa hapsedilir (thread-safe değildir); ilk
/// çağrıda kurulur ve yaşar.
public final class HighlightJSEngine: SyntaxHighlighting {
    /// Bunun üstündeki dosya düz metindir (design/03 §6 cutoff).
    public static let plainTextCutoffBytes = 1_000_000
    /// Gömülü alt dilleri olan ağır gramerler (JSX, Vue/HTML'in script/style
    /// blokları): 1 MB'lık TSX ~6 sn sürüyordu.
    static let heavyLanguageCutoffBytes = 400_000
    static let heavyLanguages: Set<String> = ["typescript", "javascript", "xml", "php"]

    /// Yükleme sırası önemlidir: ShaderLab blokları HLSL'e devreder.
    nonisolated static let grammarFiles = ["hlsl", "shaderlab", "hcl"]

    nonisolated private static let log = LumiLog.logger("highlight")

    private let style: HighlightStyle
    private let queue = DispatchQueue(label: "lumi.highlightjs", qos: .userInitiated)
    // Queue-confined: yalnız `queue` üstünde okunur/yazılır.
    nonisolated(unsafe) private var runtime: Runtime?

    public init(style: HighlightStyle = HighlightStyle()) {
        self.style = style
    }

    public func highlight(code: String, fileName: String, fontSize: CGFloat) async -> NSAttributedString {
        guard let language = HighlightLanguage.id(forFileName: fileName),
              code.utf8.count <= Self.cutoff(for: language) else {
            return plainText(code, fontSize: fontSize)
        }
        struct AttributedBox: @unchecked Sendable { let value: NSAttributedString? }
        let style = style
        let box: AttributedBox = await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let html = self?.loadedRuntime()?.highlight(code, language: language) else {
                    return continuation.resume(returning: AttributedBox(value: nil))
                }
                continuation.resume(returning: AttributedBox(
                    value: HighlightHTMLRenderer.attributed(fromHTML: html, style: style, fontSize: fontSize)
                ))
            }
        }
        // Çıktının metni girdiyle birebir aynı olmalı (editör yalnız attribute
        // uygular); değilse düz metin güvenli yoldur.
        guard let value = box.value, value.string == code else { return plainText(code, fontSize: fontSize) }
        return value
    }

    static func cutoff(for language: String) -> Int {
        heavyLanguages.contains(language) ? heavyLanguageCutoffBytes : plainTextCutoffBytes
    }

    nonisolated func plainText(_ code: String, fontSize: CGFloat) -> NSAttributedString {
        NSAttributedString(string: code, attributes: [
            .font: style.font(fontSize),
            .foregroundColor: style.plainTextColor,
        ])
    }

    /// Yalnız `queue` üstünden çağrılır.
    nonisolated private func loadedRuntime() -> Runtime? {
        if let runtime { return runtime }
        runtime = Runtime.load()
        return runtime
    }

    /// Paketlenen dillerin listesi — tablo doğrulaması (testler) için.
    func supportedLanguages() async -> Set<String> {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                continuation.resume(returning: self?.loadedRuntime()?.languages ?? [])
            }
        }
    }

    /// Kurulmuş JS ortamı.
    private final class Runtime: @unchecked Sendable {
        let hljs: JSValue
        /// Kimlikler + takma adlar; bilinmeyen kimlik hljs'e hiç gitmez.
        let languages: Set<String>

        init(hljs: JSValue, languages: Set<String>) {
            self.hljs = hljs
            self.languages = languages
        }

        static func load() -> Runtime? {
            guard let context = JSContext(),
                  let core = script(named: "highlight.min", subdirectory: nil) else { return nil }
            context.exceptionHandler = { _, exception in
                HighlightJSEngine.log.error("highlight.js: \(exception?.toString() ?? "?", privacy: .public)")
            }
            context.evaluateScript(core)
            for grammar in grammarFiles {
                if let source = script(named: grammar, subdirectory: "grammars") {
                    context.evaluateScript(source)
                } else {
                    HighlightJSEngine.log.error("highlight.js: grammar \(grammar, privacy: .public) missing")
                }
            }
            guard let hljs = context.objectForKeyedSubscript("hljs"), !hljs.isUndefined else { return nil }
            let names = hljs.invokeMethod("listLanguages", withArguments: [])?.toArray() as? [String] ?? []
            var languages = Set(names)
            for name in names {
                let aliases = hljs.invokeMethod("getLanguage", withArguments: [name])?
                    .objectForKeyedSubscript("aliases")?.toArray() as? [String]
                languages.formUnion(aliases ?? [])
            }
            return Runtime(hljs: hljs, languages: languages)
        }

        func highlight(_ code: String, language: String) -> String? {
            guard languages.contains(language),
                  let options = JSValue(object: ["language": language, "ignoreIllegals": true], in: hljs.context),
                  let result = hljs.invokeMethod("highlight", withArguments: [code, options]),
                  !result.isUndefined,
                  let value = result.objectForKeyedSubscript("value"), value.isString
            else { return nil }
            return value.toString()
        }

        private static func script(named name: String, subdirectory: String?) -> String? {
            guard let url = Bundle.module.url(forResource: name, withExtension: "js", subdirectory: subdirectory)
            else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }
    }
}
