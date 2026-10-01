import Testing
import Foundation
@testable import LumiServices
import LumiKit

@Suite struct ClaudeTranscriptChatDecoderTests {
    private let decoder = ClaudeTranscriptChatDecoder()

    @Test func decodesUserTextString() {
        let rec: [String: Any] = ["type": "user", "uuid": "u1",
                                  "message": ["content": "merhaba"]]
        let msg = decoder.decode(rec, index: 0)
        #expect(msg?.role == .user)
        #expect(msg?.blocks == [.text("merhaba", presentation: nil)])
        #expect(msg?.id == "u1")
    }

    // Karar 95: `/clear` zarfı ve yerel komut çıktısı telefona gitmez;
    // skill zarfı kullanıcının yazdığı `/name args` olarak görünür.
    @Test func dropsHarnessInjectedUserTurns() {
        let clear: [String: Any] = ["type": "user", "uuid": "c1", "message": ["content":
            "<command-name>/clear</command-name>\n            <command-message>clear</command-message>\n            <command-args></command-args>"]]
        #expect(decoder.decode(clear, index: 0) == nil)
        let stdout: [String: Any] = ["type": "user", "uuid": "c2", "message": ["content": [
            ["type": "text", "text": "<local-command-stdout>Set model to Opus</local-command-stdout>"],
        ]]]
        #expect(decoder.decode(stdout, index: 1) == nil)
        let skill: [String: Any] = ["type": "user", "uuid": "c3", "message": ["content":
            "<command-name>/brainstorm</command-name><command-args>login ekranı</command-args>"]]
        #expect(decoder.decode(skill, index: 2)?.blocks == [.text("/brainstorm login ekranı", presentation: nil)])
    }

    @Test func decodesAssistantTextAndToolUse() {
        let rec: [String: Any] = [
            "type": "assistant", "uuid": "a1",
            "message": ["content": [
                ["type": "text", "text": "düzeltiyorum"],
                ["type": "tool_use", "id": "tu1", "name": "Edit",
                 "input": ["file_path": "/x/file.swift"]],
            ]],
        ]
        let msg = decoder.decode(rec, index: 1)
        #expect(msg?.role == .assistant)
        #expect(msg?.blocks.count == 2)
        #expect(msg?.blocks[0] == .text("düzeltiyorum", presentation: nil))
        if case let .toolCall(name, preview, _) = msg?.blocks[1] {
            #expect(name == "Edit")
            #expect(preview.contains("file.swift"))
        } else { Issue.record("tool-call bekleniyordu") }
    }

    @Test func decodesToolResult() {
        let rec: [String: Any] = [
            "type": "user", "uuid": "r1",
            "message": ["content": [
                ["type": "tool_result", "tool_use_id": "tu1", "content": "tamam", "is_error": false],
            ]],
        ]
        let msg = decoder.decode(rec, index: 2)
        #expect(msg?.role == .user)
        #expect(msg?.blocks == [.toolResult(output: "tamam", isError: false)])
    }

    @Test func skipsMetaAndUnknown() {
        #expect(decoder.decode(["type": "user", "isMeta": true, "message": ["content": "x"]], index: 0) == nil)
        #expect(decoder.decode(["type": "summary"], index: 0) == nil)
    }

    @Test func returnsNilForEmptyContent() {
        #expect(decoder.decode(["type": "user", "uuid": "e1", "message": ["content": "   "]], index: 0) == nil)
        #expect(decoder.decode(["type": "assistant", "uuid": "e2", "message": ["content": []]], index: 0) == nil)
    }
}
