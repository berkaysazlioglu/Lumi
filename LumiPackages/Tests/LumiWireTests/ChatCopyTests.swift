// LumiMobile/LumiMobileKit/Tests/LumiMobileKitTests/ChatCopyTests.swift
import XCTest
import LumiWire

final class ChatCopyTests: XCTestCase {
    private func turn(_ role: ChatRole, _ blocks: [ChatBlock]) -> FoldedTurn {
        let m = ChatMessage(id: "m", role: role, blocks: blocks, timestampMs: nil, turnId: nil)
        return FoldedTurn(id: "m", message: m, toolActivity: [])
    }

    func testTextOnly() {
        XCTAssertEqual(chatCopyText(turn(.assistant, [.text("hello", presentation: nil)])), "hello")
    }

    func testMultipleTextBlocksJoinWithNewline() {
        let t = turn(.assistant, [.text("a", presentation: nil), .text("b", presentation: nil)])
        XCTAssertEqual(chatCopyText(t), "a\nb")
    }

    func testMixedTextAndToolKeepsOnlyText() {
        let t = turn(.assistant, [
            .text("hi", presentation: nil),
            .toolCall(name: "Read", inputPreview: "f", state: nil),
            .toolResult(output: "ok", isError: false),
        ])
        XCTAssertEqual(chatCopyText(t), "hi")
    }

    func testToolOnlyReturnsNil() {
        let t = turn(.assistant, [.toolCall(name: "Bash", inputPreview: "ls", state: nil)])
        XCTAssertNil(chatCopyText(t))
    }

    func testEmptyTextReturnsNil() {
        XCTAssertNil(chatCopyText(turn(.assistant, [.text("   ", presentation: nil)])))
    }
}
