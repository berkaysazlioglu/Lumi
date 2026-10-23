import Testing
import Foundation
import LumiWire
@testable import LumiKit

@Suite struct ClaudeContentBlockDecodingTests {
    @Test func decodesTextToolUseToolResultSkipsThinking() {
        let content: [[String: Any]] = [
            ["type": "thinking", "thinking": "hmm"],
            ["type": "text", "text": "Selam"],
            ["type": "tool_use", "name": "Bash", "input": ["command": "ls"]],
            ["type": "tool_result", "content": "ok", "is_error": false],
        ]
        let blocks = ClaudeContentBlockDecoding.decodeBlocks(content)
        #expect(blocks.count == 3)   // thinking atlanır
        #expect(blocks[0] == .text("Selam", presentation: nil))
        if case let .toolCall(name, preview, state) = blocks[1] {
            #expect(name == "Bash"); #expect(preview == "ls"); #expect(state == "completed")
        } else { Issue.record("tool_use bekleniyordu") }
        if case let .toolResult(output, isError) = blocks[2] {
            #expect(output == "ok"); #expect(isError == false)
        } else { Issue.record("tool_result bekleniyordu") }
    }

    /// TUI paritesi: birincil argüman (`Read(path)`), tanınmayan girdide `anahtar=değer`.
    @Test func toolPreviewShowsPrimaryArgumentLikeTheTUI() {
        func preview(_ input: [String: Any]) -> String? {
            let blocks = ClaudeContentBlockDecoding.decodeBlocks([["type": "tool_use", "name": "X", "input": input]])
            if case let .toolCall(_, preview, _) = blocks.first { return preview }
            return nil
        }
        #expect(preview(["file_path": "/p/a.swift", "limit": 20]) == "/p/a.swift")
        #expect(preview(["pattern": "foo", "path": "src"]) == "foo")
        #expect(preview(["todos": 3, "merge": true]) == "merge=1 todos=3")
    }

    @Test func stringContentBecomesSingleText() {
        #expect(ClaudeContentBlockDecoding.decodeBlocks("düz metin") == [.text("düz metin", presentation: nil)])
    }
}
