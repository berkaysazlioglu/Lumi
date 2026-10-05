import AppKit
import Foundation
import XCTest
@testable import LumiServices

/// Karar 111: highlight.js çıktısının boyanması ve paketlenen gramerler.
@MainActor
final class HighlightJSEngineTests: XCTestCase {
    private let style = HighlightStyle()

    // MARK: - HTML → run

    func testRunsCarryNestedScopesAndDecodeEntities() {
        let html = #"<span class="hljs-meta">#include <span class="hljs-string">&quot;a&amp;b&lt;&gt;&#x27;&quot;</span></span> x"#
        XCTAssertEqual(HighlightHTMLRenderer.runs(fromHTML: html), [
            .init(text: "#include ", scopes: ["meta"]),
            .init(text: "\"a&b<>'\"", scopes: ["string", "meta"]),
            .init(text: " x", scopes: []),
        ])
    }

    func testCompoundClassesBecomeDottedScopes() {
        XCTAssertEqual(HighlightHTMLRenderer.scope(fromTag: #"span class="hljs-title function_""#), "title.function")
        XCTAssertEqual(
            HighlightHTMLRenderer.scope(fromTag: #"span class="hljs-title class_ inherited__""#),
            "title.class.inherited"
        )
        XCTAssertNil(HighlightHTMLRenderer.scope(fromTag: #"span class="language-xml""#))
    }

    // MARK: - Palet

    func testScopeLookupFallsBackToLongestPrefix() {
        XCTAssertEqual(style.style(forScope: "title.function.invoke")?.color, NSColor(hex: 0x61AEEE))
        XCTAssertEqual(style.style(forScope: "title.class")?.color, NSColor(hex: 0xE6C07B))
        XCTAssertEqual(style.style(forScope: "built_in")?.color, NSColor(hex: 0xE6C07B))
        XCTAssertNil(style.style(forScope: "punctuation"))
    }

    func testInnerScopeColorWinsAndCommentsAreItalic() {
        let html = #"<span class="hljs-meta">a<span class="hljs-string">b</span></span><span class="hljs-comment">c</span>"#
        let text = HighlightHTMLRenderer.attributed(fromHTML: html, style: style, fontSize: 12)
        XCTAssertEqual(text.string, "abc")
        XCTAssertEqual(color(text, at: 0), NSColor(hex: 0x61AEEE))
        XCTAssertEqual(color(text, at: 1), NSColor(hex: 0x98C379))
        let commentFont = text.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        XCTAssertTrue(commentFont?.fontDescriptor.symbolicTraits.contains(.italic) ?? false)
    }

    // MARK: - Gerçek motor

    func testEveryMappedLanguageIsInTheBundle() async {
        let supported = await HighlightJSEngine().supportedLanguages()
        let missing = HighlightLanguage.allIDs.subtracting(supported)
        XCTAssertTrue(missing.isEmpty, "bundle'da olmayan kimlik otomatik algılamaya düşerdi: \(missing)")
    }

    func testSwiftTypesAndFunctionsGetColor() async {
        let code = "class Box: Codable {\n    func open() -> Int { print(1); return 0 }\n}\n"
        let text = await HighlightJSEngine().highlight(code: code, fileName: "Box.swift", fontSize: 12)
        XCTAssertEqual(text.string, code)
        XCTAssertEqual(color(text, of: "Box", in: code), NSColor(hex: 0xE6C07B), "title.class")
        XCTAssertEqual(color(text, of: "open", in: code), NSColor(hex: 0x61AEEE), "title.function")
        XCTAssertEqual(color(text, of: "class", in: code), NSColor(hex: 0xC678DD), "keyword")
    }

    func testShaderLabDelegatesProgramBlocksToHLSL() async {
        let code = """
        Shader "Custom/Unlit" {
            Properties { _MainTex ("Texture", 2D) = "white" {} }
            SubShader {
                Pass {
                    HLSLPROGRAM
                    float4 frag (float2 uv : TEXCOORD0) : SV_Target { return saturate(uv.xyxy); }
                    ENDHLSL
                }
            }
        }
        """
        let text = await HighlightJSEngine().highlight(code: code, fileName: "Unlit.shader", fontSize: 12)
        XCTAssertEqual(text.string, code)
        XCTAssertEqual(color(text, of: "SubShader", in: code), NSColor(hex: 0xC678DD))
        XCTAssertEqual(color(text, of: "float4", in: code), NSColor(hex: 0xD19A66), "HLSL tipi")
        XCTAssertEqual(color(text, of: "saturate", in: code), NSColor(hex: 0xE6C07B), "HLSL intrinsic")
    }

    func testTerraformBlockIsHighlighted() async {
        let code = "resource \"aws_s3_bucket\" \"logs\" {\n  bucket = \"${var.prefix}-logs\"\n}\n"
        let text = await HighlightJSEngine().highlight(code: code, fileName: "main.tf", fontSize: 12)
        XCTAssertEqual(text.string, code)
        XCTAssertEqual(color(text, of: "resource", in: code), NSColor(hex: 0xC678DD))
        XCTAssertEqual(color(text, of: "bucket =", in: code), NSColor(hex: 0xD19A66), "attr")
    }

    func testIllegalSyntaxDoesNotTurnWholeFileToPlainText() async {
        // `ignoreIllegals`: hljs'in reddettiği bir parça tüm dosyayı düşürmemeli.
        let code = "let a = 1\n\u{1}@@@ ### \u{7}\nlet b = \"x\"\n"
        let text = await HighlightJSEngine().highlight(code: code, fileName: "a.swift", fontSize: 12)
        XCTAssertEqual(text.string, code)
        XCTAssertEqual(color(text, of: "\"x\"", in: code), NSColor(hex: 0x98C379))
    }

    // MARK: - Yardımcılar

    private func color(_ text: NSAttributedString, at index: Int) -> NSColor? {
        text.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    private func color(_ text: NSAttributedString, of token: String, in code: String) -> NSColor? {
        let range = (code as NSString).range(of: token)
        guard range.location != NSNotFound else { return nil }
        return color(text, at: range.location)
    }
}
