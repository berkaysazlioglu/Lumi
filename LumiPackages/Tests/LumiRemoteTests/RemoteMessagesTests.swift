import LumiKit
import XCTest
@testable import LumiRemote

final class RemoteMessagesTests: XCTestCase {
    // MARK: - Client decode

    func testDecodesAttachMessage() {
        let message = RemoteMessageCodec.decodeClient(#"{"type":"attach","id":"ABC"}"#)
        XCTAssertEqual(message, .attach(id: "ABC"))
    }

    func testDecodesInputMessageWithEscapeBytes() {
        let message = RemoteMessageCodec.decodeClient(#"{"type":"input","data":"\u001b[A"}"#)
        XCTAssertEqual(message, .input(data: "\u{1B}[A"))
    }

    func testDecodesPromptMessage() {
        let message = RemoteMessageCodec.decodeClient(#"{"type":"prompt","text":"merhaba"}"#)
        XCTAssertEqual(message, .prompt(text: "merhaba"))
    }

    func testReturnsNilForUnknownType() {
        XCTAssertNil(RemoteMessageCodec.decodeClient(#"{"type":"resize","cols":80}"#))
    }

    func testReturnsNilForMalformedJSON() {
        XCTAssertNil(RemoteMessageCodec.decodeClient("not json"))
    }

    func testReturnsNilWhenRequiredFieldMissing() {
        XCTAssertNil(RemoteMessageCodec.decodeClient(#"{"type":"attach"}"#))
        XCTAssertNil(RemoteMessageCodec.decodeClient(#"{"type":"input"}"#))
        XCTAssertNil(RemoteMessageCodec.decodeClient(#"{"type":"prompt"}"#))
    }

    // MARK: - Server encode

    func testEncodesSnapshotWithStyledScreenAndTerminalSummary() throws {
        let terminal = RemoteTerminalSummary(
            id: "T1", name: "Terminal 1", repoPath: "/tmp/repo", repoName: "repo",
            status: "working", task: nil, title: nil
        )
        let snapshot = TerminalScreenSnapshot(
            history: "eski satırlar",
            screen: [[
                TerminalScreenRun(text: "kırmızı", foreground: "#ff0000", flags: 1),
                TerminalScreenRun(text: " düz"),
            ]]
        )
        let json = RemoteMessageCodec.encodeServer(.snapshot(snapshot: snapshot, terminal: terminal))

        let decoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        XCTAssertEqual(decoded["type"] as? String, "snapshot")
        XCTAssertEqual(decoded["history"] as? String, "eski satırlar")
        let screen = try XCTUnwrap(decoded["screen"] as? [[[String: Any]]])
        XCTAssertEqual(screen.count, 1)
        XCTAssertEqual(screen[0][0]["t"] as? String, "kırmızı")
        XCTAssertEqual(screen[0][0]["fg"] as? String, "#ff0000")
        XCTAssertEqual(screen[0][0]["f"] as? Int, 1)
        XCTAssertEqual(screen[0][1]["t"] as? String, " düz")
        XCTAssertNil(screen[0][1]["fg"])
        let terminalDict = try XCTUnwrap(decoded["terminal"] as? [String: Any])
        XCTAssertEqual(terminalDict["status"] as? String, "working")
        XCTAssertEqual(terminalDict["repoName"] as? String, "repo")
    }

    func testEncodesExitedAndError() {
        XCTAssertTrue(RemoteMessageCodec.encodeServer(.exited).contains(#""type":"exited""#))
        let error = RemoteMessageCodec.encodeServer(.error(message: "boom"))
        XCTAssertTrue(error.contains(#""type":"error""#))
        XCTAssertTrue(error.contains("boom"))
    }
}

final class SnapshotClipperTests: XCTestCase {
    func testReturnsTextUnchangedWhenWithinLimit() {
        XCTAssertEqual(SnapshotClipper.tail("a\nb\nc", maxLines: 5), "a\nb\nc")
    }

    func testReturnsOnlyTailWhenOverLimit() {
        let text = (1...10).map(String.init).joined(separator: "\n")
        XCTAssertEqual(SnapshotClipper.tail(text, maxLines: 3), "8\n9\n10")
    }

    func testPreservesEmptyLinesInsideTail() {
        XCTAssertEqual(SnapshotClipper.tail("a\n\nb\n\nc", maxLines: 3), "b\n\nc")
    }
}
