import Foundation
import XCTest
@testable import LumiUI

/// `HighlightrEngine`'in SAF dil eşlemesi ve düz-metin cutoff sınırı
/// (refactor plan 2.8). JSCore'a hiç girilmez — yalnız tablo davranışı.
@MainActor
final class SyntaxHighlightingLanguageTests: XCTestCase {
    private func language(_ name: String) -> String? {
        HighlightrEngine.language(forFileName: name)
    }

    // MARK: - Dosya adı özel durumları

    func testDockerfileIsMatchedByNameNotExtension() {
        XCTAssertEqual(language("Dockerfile"), "dockerfile")
        XCTAssertEqual(language("dockerfile"), "dockerfile")
        XCTAssertEqual(language("build/Dockerfile"), "dockerfile", "yalnız son bileşene bakılır")
    }

    func testDockerfileWithSuffixIsNotMatched() {
        // Mevcut davranış: tam ad eşleşmesi — "Dockerfile.dev" uzantı yoluna düşer
        // ("dev" tabloda yok) → nil.
        XCTAssertNil(language("Dockerfile.dev"))
    }

    func testExtensionlessFileHasNoLanguage() {
        XCTAssertNil(language("LICENSE"))
        XCTAssertNil(language("Makefile"))
        XCTAssertNil(language(""))
    }

    func testPlainTextExtensionIsExplicitlyUnhighlighted() {
        XCTAssertNil(language("notes.txt"))
    }

    func testUnknownExtensionFallsBackToNil() {
        XCTAssertNil(language("data.parquet"))
        XCTAssertNil(language("archive.tar.gz"))
    }

    func testLookupIsCaseInsensitive() {
        XCTAssertEqual(language("Main.SWIFT"), "swift")
        XCTAssertEqual(language("App.TSX"), "typescript")
        XCTAssertEqual(language("Style.CSS"), "css")
    }

    func testExtensionAliasesShareOneLanguage() {
        XCTAssertEqual(language("a.ts"), language("a.tsx"))
        XCTAssertEqual(language("a.js"), "javascript")
        XCTAssertEqual(language("a.mjs"), "javascript")
        XCTAssertEqual(language("a.cjs"), "javascript")
        XCTAssertEqual(language("a.yml"), language("a.yaml"))
        XCTAssertEqual(language("a.htm"), "xml", "html → xml grameri")
        XCTAssertEqual(language("a.svg"), "xml")
        XCTAssertEqual(language("a.markdown"), "markdown")
    }

    func testDotfileIsTreatedAsExtensionByFoundation() {
        // Mevcut davranışın belgelenmesi: `(".gitignore" as NSString).pathExtension`
        // boş döner → nil (dosya adı "gitignore" gibi ele alınmaz).
        XCTAssertNil(language(".gitignore"))
    }

    // MARK: - Cutoff sınırı

    func testPlainTextCutoffIsOneMegabyte() {
        XCTAssertEqual(HighlightrEngine.plainTextCutoffBytes, 1_000_000)
    }

    func testCutoffCompareUsesUTF8ByteCountNotCharacterCount() async {
        // Sınırın hemen ALTINDA çok baytlı içerik: karakter sayısı sınırın altında
        // olsa da UTF-8 bayt sayısı aşarsa düz metne düşmeli.
        let engine = HighlightrEngine()
        let multibyte = String(repeating: "ü", count: HighlightrEngine.plainTextCutoffBytes / 2 + 1)
        XCTAssertGreaterThan(multibyte.utf8.count, HighlightrEngine.plainTextCutoffBytes)
        XCTAssertLessThan(multibyte.count, HighlightrEngine.plainTextCutoffBytes)

        let result = await engine.highlight(code: multibyte, fileName: "big.swift", fontSize: 12)
        // Düz metin yolu: attribute'lar tek run halinde (highlight edilmiş metinde
        // birden çok renk run'ı olurdu).
        XCTAssertEqual(result.string, multibyte)
        var runCount = 0
        result.enumerateAttributes(in: NSRange(location: 0, length: result.length)) { _, _, _ in
            runCount += 1
        }
        XCTAssertEqual(runCount, 1, "cutoff üstü içerik tek run'lı düz metin olmalı")
    }

    func testUnknownLanguageAlwaysUsesPlainTextPath() async {
        let engine = HighlightrEngine()
        let code = "hello world"
        let result = await engine.highlight(code: code, fileName: "notes.txt", fontSize: 12)
        XCTAssertEqual(result.string, code)
    }
}
