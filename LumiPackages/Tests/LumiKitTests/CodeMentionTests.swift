import Foundation
import XCTest
@testable import LumiKit

/// Karar 100: FileViewer seçimi → `@path#L…` referansı.
final class CodeMentionTests: XCTestCase {
    private let text = "line1\nline2\nline3\nline4\n"

    private func range(of substring: String) -> NSRange {
        (text as NSString).range(of: substring)
    }

    func testEmptySelectionHasNoRange() {
        XCTAssertNil(CodeMention.lineRange(in: text, selection: NSRange(location: 3, length: 0)))
        XCTAssertNil(CodeMention.lineRange(in: text, selection: NSRange(location: NSNotFound, length: 0)))
    }

    func testSelectionInsideOneLine() {
        XCTAssertEqual(CodeMention.lineRange(in: text, selection: range(of: "ine2")), 2...2)
    }

    func testSelectionAcrossLines() {
        XCTAssertEqual(CodeMention.lineRange(in: text, selection: range(of: "2\nline3\nli")), 2...4)
    }

    func testTrailingNewlineDoesNotPullInNextLine() {
        XCTAssertEqual(CodeMention.lineRange(in: text, selection: range(of: "line2\nline3\n")), 2...3)
    }

    func testOnlyNewlineSelectedStaysOnItsLine() {
        XCTAssertEqual(CodeMention.lineRange(in: text, selection: NSRange(location: 5, length: 1)), 1...1)
    }

    func testOutOfBoundsSelectionIsRejected() {
        XCTAssertNil(CodeMention.lineRange(in: text, selection: NSRange(location: 20, length: 10)))
    }

    func testReferenceUsesRangeOrSingleLineAndTrailingSpace() {
        XCTAssertEqual(
            CodeMention.reference(filePath: "Assets/A.cs", repoPath: "/repo", lines: 12...18),
            "@Assets/A.cs#L12-18 "
        )
        XCTAssertEqual(
            CodeMention.reference(filePath: "Assets/A.cs", repoPath: "/repo", lines: 7...7),
            "@Assets/A.cs#L7 "
        )
    }

    func testAbsolutePathInsideRepoBecomesRelative() {
        XCTAssertEqual(
            CodeMention.reference(filePath: "/repo/src/x.swift", repoPath: "/repo/", lines: 1...2),
            "@src/x.swift#L1-2 "
        )
        XCTAssertEqual(CodeMention.relativePath("/repository/x", in: "/repo"), "/repository/x")
    }

    func testEncodePasteHasNoSubmit() {
        XCTAssertEqual(PromptInjection.encodePaste("@a#L1 "), "\u{1B}[200~@a#L1 \u{1B}[201~")
    }
}
