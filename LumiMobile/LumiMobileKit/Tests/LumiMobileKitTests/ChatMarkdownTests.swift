import XCTest
@testable import LumiMobileKit

final class ChatMarkdownTests: XCTestCase {
    func testSplitsFencedCodeBlocks() {
        let text = "Intro `Foo`\n```swift\nlet x = 1\n```\nAfter"
        XCTAssertEqual(chatMarkdownSegments(text), [
            .prose("Intro `Foo`"),
            .code(language: "swift", body: "let x = 1"),
            .prose("After"),
        ])
    }

    func testUnterminatedFenceStillRendersAsCode() {   // streaming mid-block
        XCTAssertEqual(chatMarkdownSegments("a\n```\nb"), [.prose("a"), .code(language: nil, body: "b")])
    }

    func testPlainTextIsSingleProse() {
        XCTAssertEqual(chatMarkdownSegments("hello\nworld"), [.prose("hello\nworld")])
    }

    func testInlineCodeRunsAreMarked() {
        let attr = chatInlineAttributed("Use `AppModel` and **bold**")
        let codeRuns = attr.runs.filter { $0.inlinePresentationIntent?.contains(.code) == true }
        XCTAssertEqual(codeRuns.map { String(attr[$0.range].characters) }, ["AppModel"])
        XCTAssertEqual(String(attr.characters), "Use AppModel and bold")
    }

    func testInlinePreservesNewlines() {
        XCTAssertEqual(String(chatInlineAttributed("a\nb").characters), "a\nb")
    }
}
