import AppKit
import Foundation
import XCTest
@testable import LumiServices

/// Karar 111: dosya adı → dil tablosu ve düz-metin cutoff sınırları
/// (refactor plan 2.8). JSCore'a girilmez — yalnız tablo davranışı.
@MainActor
final class SyntaxHighlightingLanguageTests: XCTestCase {
    private func language(_ name: String) -> String? {
        HighlightLanguage.id(forFileName: name)
    }

    // MARK: - Dosya adı özel durumları

    func testExactNamesWinOverExtensions() {
        XCTAssertEqual(language("Dockerfile"), "dockerfile")
        XCTAssertEqual(language("build/Dockerfile"), "dockerfile", "yalnız son bileşene bakılır")
        XCTAssertEqual(language("Makefile"), "makefile")
        XCTAssertEqual(language("CMakeLists.txt"), "cmake", "tam ad .txt'yi ezer")
        XCTAssertEqual(language("Podfile"), "ruby")
        XCTAssertEqual(language("Jenkinsfile"), "groovy")
        XCTAssertEqual(language(".zshrc"), "bash")
    }

    func testPrefixPatterns() {
        XCTAssertEqual(language("Dockerfile.dev"), "dockerfile")
        XCTAssertEqual(language(".env.local"), "properties")
        XCTAssertEqual(language(".env"), "properties")
    }

    func testPlainFilesStayUnhighlighted() {
        XCTAssertNil(language("LICENSE"))
        XCTAssertNil(language("notes.txt"))
        XCTAssertNil(language(".gitignore"))
        XCTAssertNil(language("data.parquet"))
        XCTAssertNil(language(""))
    }

    func testLookupIsCaseInsensitive() {
        XCTAssertEqual(language("Main.SWIFT"), "swift")
        XCTAssertEqual(language("App.TSX"), "typescript")
        XCTAssertEqual(language("PODFILE"), "ruby")
    }

    func testCommonLanguagesAreMapped() {
        let expected: [String: String] = [
            "a.cs": "csharp", "a.m": "objectivec", "a.mm": "objectivec", "a.dart": "dart",
            "a.php": "php", "a.lua": "lua", "a.kt": "kotlin", "a.gradle": "gradle",
            "a.ps1": "powershell", "a.vue": "xml", "a.scala": "scala", "a.ex": "elixir",
            "a.proto": "protobuf", "a.toml": "ini", "a.plist": "xml", "a.csproj": "xml",
        ]
        for (file, id) in expected { XCTAssertEqual(language(file), id, file) }
    }

    func testUnityFilesAreMapped() {
        XCTAssertEqual(language("Main.unity"), "yaml")
        XCTAssertEqual(language("Player.prefab"), "yaml")
        XCTAssertEqual(language("Player.prefab.meta"), "yaml")
        XCTAssertEqual(language("Game.asmdef"), "json")
        XCTAssertEqual(language("Panel.uxml"), "xml")
        XCTAssertEqual(language("Panel.uss"), "css")
        XCTAssertEqual(language("Lit.shader"), "shaderlab")
        XCTAssertEqual(language("Common.cginc"), "hlsl")
        XCTAssertEqual(language("Blur.compute"), "hlsl")
    }

    func testTerraformUsesLumiGrammar() {
        XCTAssertEqual(language("main.tf"), "hcl")
        XCTAssertEqual(language("prod.tfvars"), "hcl")
    }

    // MARK: - Cutoff sınırı

    func testHeavyLanguagesHaveLowerCutoff() {
        XCTAssertEqual(HighlightJSEngine.cutoff(for: "swift"), 1_000_000)
        XCTAssertEqual(HighlightJSEngine.cutoff(for: "typescript"), 400_000)
        XCTAssertEqual(HighlightJSEngine.cutoff(for: "xml"), 400_000)
    }

    func testCutoffCompareUsesUTF8ByteCountNotCharacterCount() async {
        let engine = HighlightJSEngine()
        let multibyte = String(repeating: "ü", count: HighlightJSEngine.plainTextCutoffBytes / 2 + 1)
        XCTAssertGreaterThan(multibyte.utf8.count, HighlightJSEngine.plainTextCutoffBytes)
        XCTAssertLessThan(multibyte.count, HighlightJSEngine.plainTextCutoffBytes)

        let result = await engine.highlight(code: multibyte, fileName: "big.swift", fontSize: 12)
        XCTAssertEqual(result.string, multibyte)
        XCTAssertEqual(runCount(result), 1, "cutoff üstü içerik tek run'lı düz metin olmalı")
    }

    func testUnknownLanguageAlwaysUsesPlainTextPath() async {
        let engine = HighlightJSEngine()
        let result = await engine.highlight(code: "hello world", fileName: "notes.txt", fontSize: 12)
        XCTAssertEqual(result.string, "hello world")
        XCTAssertEqual(runCount(result), 1)
    }

    private func runCount(_ text: NSAttributedString) -> Int {
        var count = 0
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { _, _, _ in count += 1 }
        return count
    }
}
