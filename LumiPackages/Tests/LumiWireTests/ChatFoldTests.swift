// LumiPackages/Tests/LumiWireTests/ChatFoldTests.swift
import XCTest
import LumiWire

final class ChatFoldTests: XCTestCase {
    private func msg(_ id: String, _ role: ChatRole, _ blocks: [ChatBlock]) -> ChatMessage {
        ChatMessage(id: id, role: role, blocks: blocks, timestampMs: nil, turnId: nil)
    }

    func testFoldsToolOnlyIntoPrecedingTextTurn() {
        let messages = [
            msg("a1", .assistant, [.text("looking", presentation: nil)]),
            msg("a2", .assistant, [.toolCall(name: "Read", inputPreview: "f", state: nil)]),
            msg("u1", .user, [.toolResult(output: "ok", isError: false)]),
            msg("a3", .assistant, [.text("fixed", presentation: nil)]),
        ]
        let folded = foldChatMessages(messages)
        XCTAssertEqual(folded.count, 2)               // two text turns
        XCTAssertEqual(folded[0].message.id, "a1")
        XCTAssertEqual(folded[0].toolActivity.map(\.id), ["a2", "u1"])
        XCTAssertEqual(folded[1].message.id, "a3")
        XCTAssertTrue(folded[1].toolActivity.isEmpty)
    }

    func testLeadingToolOnlyBecomesOwnTurn() {
        // If there is no preceding text turn, the tool-only message becomes its own turn (not dropped).
        let folded = foldChatMessages([msg("a1", .assistant, [.toolCall(name: "Bash", inputPreview: "ls", state: nil)])])
        XCTAssertEqual(folded.count, 1)
        XCTAssertEqual(folded[0].message.id, "a1")
    }
}
