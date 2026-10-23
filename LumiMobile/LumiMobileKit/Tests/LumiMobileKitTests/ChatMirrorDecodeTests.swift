import XCTest
@testable import LumiMobileKit
import LumiWire

final class ChatMirrorDecodeTests: XCTestCase {
    func testDecodeChatFrame() {
        let frame = #"""
        {"v":1,"type":"chat","payload":{"sessionId":"s1","messages":[
          {"id":"m1","role":"user","timestamp":5,"blocks":[{"type":"text","text":"hi"}]},
          {"id":"m2","role":"assistant","timestamp":null,"blocks":[
            {"type":"tool-call","name":"Edit","inputPreview":"file.swift"},
            {"type":"tool-result","output":"ok","isError":false}]}]}}
        """#
        guard case let .chat(sessionId, messages, _)? = PhoneProtocol.decodeServerMessage(frame) else {
            return XCTFail("chat could not be decoded")
        }
        XCTAssertEqual(sessionId, "s1")
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .user)
        XCTAssertEqual(messages[0].blocks, [.text("hi", presentation: nil)])
        XCTAssertEqual(messages[1].blocks.first, .toolCall(name: "Edit", inputPreview: "file.swift", state: nil))
    }

    func testDecodeChatAppendFrame() {
        let frame = #"{"v":1,"type":"chat_append","payload":{"sessionId":"s1","messages":[{"id":"m3","role":"assistant","blocks":[{"type":"text","text":"done"}]}]}}"#
        guard case let .chatAppend(_, messages, _)? = PhoneProtocol.decodeServerMessage(frame) else {
            return XCTFail("chat_append could not be decoded")
        }
        XCTAssertEqual(messages.first?.id, "m3")
    }

    func testSubscribeFrameCarriesMode() {
        let frame = PhoneProtocol.subscribeFrame(sessionId: "s1", mode: "chat")
        XCTAssertTrue(frame.contains("\"mode\":\"chat\""))
    }

    func testDecodeBlockVariantsAndTolerance() {
        let frame = #"""
        {"v":1,"type":"chat","payload":{"sessionId":"s1","messages":[
          {"id":"m1","role":"assistant","timestamp":7,"turnId":"t1","blocks":[
            {"type":"image-ref","path":"/a.png","alt":"pic"},
            {"type":"code-fence","lang":"swift"}]},
          {"role":"assistant","blocks":[{"type":"text","text":"no id → dropped"}]}]}}
        """#
        guard case let .chat(_, messages, _)? = PhoneProtocol.decodeServerMessage(frame) else {
            return XCTFail("chat could not be decoded")
        }
        XCTAssertEqual(messages.count, 1, "message without id is dropped by compactMap")
        XCTAssertEqual(messages[0].timestampMs, 7)
        XCTAssertEqual(messages[0].turnId, "t1")
        XCTAssertEqual(messages[0].blocks[0], .imageRef(path: "/a.png", url: nil, alt: "pic"))
        XCTAssertEqual(messages[0].blocks[1], .unknown, "unknown block type → .unknown")
    }
}
