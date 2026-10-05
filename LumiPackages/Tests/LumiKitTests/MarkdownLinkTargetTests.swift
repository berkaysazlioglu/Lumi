import LumiKit
import XCTest

/// Karar 109: render'lı markdown'da link tıklamasının hedefi.
final class MarkdownLinkTargetTests: XCTestCase {
    private func resolve(_ destination: String, from file: String = "Assets/Docs/Reports/Report.md") -> MarkdownLinkTarget {
        MarkdownLinkTarget.resolve(URL(string: destination)!, from: file)
    }

    func testSchemedLinksGoToSystem() {
        XCTAssertEqual(resolve("https://github.com/x"), .external(URL(string: "https://github.com/x")!))
        XCTAssertEqual(resolve("mailto:a@b.dev"), .external(URL(string: "mailto:a@b.dev")!))
    }

    func testRelativeLinkResolvesAgainstFileDirectory() {
        XCTAssertEqual(resolve("Other.md"), .file("Assets/Docs/Reports/Other.md"))
        XCTAssertEqual(resolve("./sub/Deep.md#intro"), .file("Assets/Docs/Reports/sub/Deep.md"))
        XCTAssertEqual(resolve("../../README.md"), .file("Assets/README.md"))
        XCTAssertEqual(resolve("My%20Notes.md"), .file("Assets/Docs/Reports/My Notes.md"))
    }

    func testLeadingSlashIsRepoRootRelative() {
        XCTAssertEqual(resolve("/docs/setup.md"), .file("docs/setup.md"))
    }

    func testAnchorAndEscapingPaths() {
        XCTAssertEqual(resolve("#summary"), .anchor)
        XCTAssertEqual(resolve("../../../../../etc/passwd"), .invalid)
        XCTAssertEqual(resolve("..", from: "README.md"), .invalid)
    }

    func testCodeLanguageFileNames() {
        XCTAssertEqual(MarkdownCodeLanguage.fileName(for: "Swift"), "snippet.swift")
        XCTAssertEqual(MarkdownCodeLanguage.fileName(for: "csharp"), "snippet.cs")
        XCTAssertEqual(MarkdownCodeLanguage.fileName(for: "bash"), "snippet.sh")
        XCTAssertNil(MarkdownCodeLanguage.fileName(for: nil))
        XCTAssertNil(MarkdownCodeLanguage.fileName(for: ""))
    }
}
