import Foundation
import XCTest
@testable import LumiKit

/// Karar 116: terminal satırındaki link adayları (Orca `terminal-links.test` vakaları).
final class TerminalLinkDetectorTests: XCTestCase {
    private func texts(_ line: String) -> [String] {
        TerminalLinkDetector.links(in: line).map(\.text)
    }

    private func firstCandidate(_ line: String, at needle: String) -> DetectedTerminalLink? {
        let offset = (line as NSString).range(of: needle).location
        return TerminalLinkDetector.candidates(in: line, at: offset).first
    }

    // MARK: - URL

    func testHTTPURLTrimsTrailingPunctuation() {
        let links = TerminalLinkDetector.links(in: "see https://lumi.dev/docs?a=1, then.")
        XCTAssertEqual(links.map(\.text), ["https://lumi.dev/docs?a=1"])
        XCTAssertEqual(links.first?.kind, .url)
        XCTAssertEqual(links.first?.requiresExistence, false)
    }

    func testURLNeedsWordBoundary() {
        XCTAssertEqual(texts("xhttps://lumi.dev"), [])
    }

    /// URL host'u yerel yol ya da çıplak dosya adı sayılmaz.
    func testURLHostIsNotAFilePath() {
        let links = TerminalLinkDetector.links(in: "PR opened: https://github.com/stablyai/orca/pull/82")
        XCTAssertEqual(links.map(\.kind), [.url])
    }

    // MARK: - Yollar

    func testFrameworkRouteKeepsParenAndBracketSegments() {
        let line = "Error in app/(shop)/products/[productId]/page.tsx:42:7"
        XCTAssertEqual(texts(line), ["app/(shop)/products/[productId]/page.tsx:42:7"])
    }

    func testExtensionlessRelativePathsAreCandidates() {
        XCTAssertEqual(texts("cd src/foo && ls ./bin"), ["src/foo && ls ./bin", "src/foo", "./bin"])
    }

    func testTildeAndAbsolutePaths() {
        XCTAssertEqual(texts("~/Documents/Path/file_name"), ["~/Documents/Path/file_name"])
        XCTAssertEqual(texts("wrote /tmp/out.log."), ["/tmp/out.log"])
    }

    func testSurroundingPunctuationIsTrimmed() {
        XCTAssertEqual(texts("(see src/App.swift)"), ["src/App.swift"])
        XCTAssertEqual(texts("\"Sources/A.swift\","), ["Sources/A.swift"])
    }

    func testSpacedAbsolutePathStopsBeforeProse() {
        let line = "Open /Users/Path/FolderName with Space/content.js for details"
        XCTAssertEqual(
            firstCandidate(line, at: "with")?.text,
            "/Users/Path/FolderName with Space/content.js"
        )
    }

    func testLineEndingSpacedFolderIsOneCandidate() {
        XCTAssertEqual(
            firstCandidate("/Users/alice/My Folder   ", at: "Folder")?.text,
            "/Users/alice/My Folder"
        )
    }

    /// Orca'dan bilinçli fark: boşluklu aday diskte yoksa düz yol yine denenir.
    func testPlainPathStaysCandidateUnderSpacedOne() {
        let line = "src/foo is great"
        let offset = 1
        XCTAssertEqual(
            TerminalLinkDetector.candidates(in: line, at: offset).map(\.text),
            ["src/foo is great", "src/foo is", "src/foo"]
        )
    }

    func testRootOnlyAndRelativeTrailingSeparatorsAreNotLinks() {
        XCTAssertEqual(texts("progress 1 / 3"), [])
        XCTAssertEqual(texts("/"), [])
        XCTAssertEqual(texts("./"), [])
        XCTAssertEqual(texts("~/"), [])
        XCTAssertEqual(texts("/Users/alice/worktree/"), ["/Users/alice/worktree/"])
    }

    // MARK: - Çıplak dosya adları

    func testBareFilenamesInLsOutput() {
        XCTAssertEqual(
            texts("CLAUDE.md    package.json    pnpm-lock.yaml    README.md"),
            ["CLAUDE.md", "package.json", "pnpm-lock.yaml", "README.md"]
        )
        XCTAssertEqual(
            TerminalLinkDetector.links(in: "README.md").map(\.kind),
            [.bareFilename]
        )
    }

    func testExtensionlessProjectFilesOnly() {
        XCTAssertEqual(
            texts("Makefile LICENSE README Dockerfile src tests").sorted(),
            ["Dockerfile", "LICENSE", "Makefile", "README"]
        )
    }

    func testProseNumbersAndFlagsAreNotFilenames() {
        XCTAssertEqual(texts("42 100 .. . -v --verbose src dist"), [])
    }

    func testBareFilenameKeepsLineSuffixAndDropsPunctuation() {
        XCTAssertEqual(texts("foo.ts:12:3 failed"), ["foo.ts:12:3"])
        XCTAssertEqual(texts("See package.json, pnpm-lock.yaml."), ["package.json", "pnpm-lock.yaml"])
    }

    func testBareTokenInsidePathIsNotDoubleLinked() {
        XCTAssertEqual(texts("./src/file.ts is the entry point"), ["./src/file.ts"])
    }

    // MARK: - file://

    func testFileURIIsOneLinkWithoutBarePathDuplicate() {
        let links = TerminalLinkDetector.links(in: "open file:///Users/dev/orca/report.html now")
        XCTAssertEqual(links.map(\.text), ["file:///Users/dev/orca/report.html"])
        XCTAssertEqual(links.first?.kind, .fileURI)
    }

    func testFileURITrimsOnlyUnbalancedClosers() {
        XCTAssertEqual(texts("(file:///tmp/a(1).txt)."), ["file:///tmp/a(1).txt"])
    }

    /// Host'lu URI yerel değildir; gövdesi de yol adayı olmaz.
    func testRemoteHostFileURIIsIgnored() {
        XCTAssertEqual(TerminalLinkDetector.links(in: "file://server/share/a.txt"), [])
    }

    // MARK: - Aday sırası

    func testURLWinsOverPathAtSameOffset() {
        let line = "https://example.com/a/b.html"
        XCTAssertEqual(firstCandidate(line, at: "a/b")?.kind, .url)
    }

    func testOffsetOutsideAnyLinkHasNoCandidates() {
        XCTAssertEqual(TerminalLinkDetector.candidates(in: "edit src/a.ts now", at: 1), [])
    }

    func testHugeLineIsSkipped() {
        let line = String(repeating: "a/", count: TerminalLinkDetector.maxLineLength)
        XCTAssertEqual(TerminalLinkDetector.links(in: line), [])
    }
}
