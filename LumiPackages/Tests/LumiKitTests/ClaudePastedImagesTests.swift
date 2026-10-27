import Foundation
import XCTest
@testable import LumiKit

/// Karar 139: Claude'un yapıştırılan görselleri — dizin, yer tutucu, liste.
final class ClaudePastedImagesTests: XCTestCase {
    func testDirectoryEncodesCwdLikeClaudeProjects() {
        XCTAssertEqual(
            ClaudePastedImages.directory(cwd: "/Users/dev.name/wk/Lumi", sessionID: "abc", userID: 502),
            "/private/tmp/claude-502/-Users-dev-name-wk-Lumi/abc/images"
        )
    }

    func testDirectoryNeedsTrackedClaudeSession() {
        let shell = TerminalMeta(id: TerminalID(), name: "t", repoPath: "/p", createdAt: Date())
        XCTAssertNil(ClaudePastedImages.directory(for: shell, userID: 1))
        var claude = shell
        claude.claudeSessionID = "s1"
        XCTAssertEqual(ClaudePastedImages.directory(for: claude, userID: 1), "/private/tmp/claude-1/-p/s1/images")
    }

    func testReferenceRoundTrip() {
        XCTAssertEqual(ClaudePastedImages.reference(3), "[Image #3]")
        XCTAssertEqual(ClaudePastedImages.number(inReference: "[Image #12]"), 12)
        XCTAssertNil(ClaudePastedImages.number(inReference: "[Image #0]"))
        XCTAssertNil(ClaudePastedImages.number(inReference: "x [Image #1]"))
        XCTAssertNil(ClaudePastedImages.number(inReference: "[Image #1] "))
    }

    func testImagesAreSortedByNumberAndPreferPNG() {
        let images = ClaudePastedImages.images(
            fileNames: ["10.png", "2.jpg", "2.png", "notes.txt", "01.png", "a.png", "3.PNG", ".DS_Store"],
            in: "/d"
        )
        XCTAssertEqual(images.map(\.path), ["/d/2.png", "/d/3.PNG", "/d/10.png"])
        XCTAssertEqual(images.first?.reference, "[Image #2]")
        XCTAssertEqual(images.first?.directory, "/d")
        XCTAssertEqual(images.first?.fileName, "2.png")
    }

    func testDetectorFindsPlaceholder() {
        let line = "❯ [Image #1] bunu düzelt [Image #22]"
        let links = TerminalLinkDetector.links(in: line).filter { $0.kind == .pastedImage }
        XCTAssertEqual(links.map(\.text), ["[Image #1]", "[Image #22]"])
        let offset = (line as NSString).range(of: "#22").location
        XCTAssertEqual(TerminalLinkDetector.candidates(in: line, at: offset).first?.text, "[Image #22]")
        XCTAssertEqual(links.first?.requiresExistence, true)
    }
}
