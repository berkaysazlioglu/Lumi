import XCTest
import LumiWire

final class ChatStreamingGateTests: XCTestCase {
    func testStreamingVisibleWhenLeadingLastMessage() {
        // show when streaming text goes beyond the last message; hide when contained/shorter (orca gate)
        XCTAssertEqual(chatStreamingText(working: true, streaming: "Hello world",
                                         lastAssistantText: "Hello"), "Hello world")
        XCTAssertNil(chatStreamingText(working: true, streaming: "Hello",
                                       lastAssistantText: "Hello world"))   // caught up
        XCTAssertNil(chatStreamingText(working: false, streaming: "x", lastAssistantText: ""))  // idle
        XCTAssertNil(chatStreamingText(working: true, streaming: nil, lastAssistantText: ""))
    }
}
