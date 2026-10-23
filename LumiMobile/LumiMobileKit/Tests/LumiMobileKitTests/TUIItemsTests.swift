import XCTest
@testable import LumiMobileKit
import LumiWire

final class TUIItemsTests: XCTestCase {
    private func msg(_ id: String, _ role: ChatRole, _ blocks: [ChatBlock]) -> ChatMessage {
        ChatMessage(id: id, role: role, blocks: blocks, timestampMs: nil, turnId: nil)
    }

    func testToolResultsPairWithTheirCallsInOrder() {
        let turn = foldChatMessages([
            msg("a1", .assistant, [.text("Looking", presentation: nil),
                                   .toolCall(name: "Read", inputPreview: "a.swift", state: nil),
                                   .toolCall(name: "Bash", inputPreview: "swift test", state: nil)]),
            msg("u1", .user, [.toolResult(output: "12 lines", isError: false)]),
            msg("u2", .user, [.toolResult(output: "1 failure", isError: true)]),
        ])[0]
        XCTAssertEqual(tuiItems(for: turn), [
            .assistant("Looking"),
            .tool(name: "Read", preview: "a.swift", result: TUIToolResult(output: "12 lines", isError: false)),
            .tool(name: "Bash", preview: "swift test", result: TUIToolResult(output: "1 failure", isError: true)),
        ])
    }

    func testRunningToolHasNoResultAndUserTextIsAPrompt() {
        XCTAssertEqual(tuiItems(for: foldChatMessages([msg("u", .user, [.text("fix it", presentation: nil)])])[0]),
                       [.user("fix it")])
        let running = foldChatMessages([msg("a", .assistant, [.toolCall(name: "Grep", inputPreview: "foo", state: nil)])])[0]
        XCTAssertEqual(tuiItems(for: running), [.tool(name: "Grep", preview: "foo", result: nil)])
    }

    func testOrphanResultIsKept() {
        let turn = foldChatMessages([msg("a", .assistant, [.text("x", presentation: nil), .toolResult(output: "late", isError: false)])])[0]
        XCTAssertEqual(tuiItems(for: turn).last, .tool(name: "", preview: "", result: TUIToolResult(output: "late", isError: false)))
    }
}
