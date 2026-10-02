import Testing
import Foundation
import LumiWire
@testable import LumiKit

@Suite struct StreamJsonEventTests {
    @Test func decodesSystemInit() {
        let line = #"{"type":"system","subtype":"init","cwd":"/repo","session_id":"S1"}"#
        #expect(StreamJsonEvent.decode(line) == .systemInit(sessionID: "S1", cwd: "/repo"))
    }
    @Test func decodesVisibleTextDeltaOnly() {
        let text = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}}"#
        #expect(StreamJsonEvent.decode(text) == .streamTextDelta("Hel"))
        // thinking_delta streaming metnine katılmaz → ignored
        let think = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hmm"}}}"#
        #expect(StreamJsonEvent.decode(think) == .ignored)
    }
    @Test func decodesAssistantSnapshot() {
        let line = #"{"type":"assistant","message":{"role":"assistant","id":"msg_1","content":[{"type":"text","text":"Selam"}]}}"#
        #expect(StreamJsonEvent.decode(line) == .assistantSnapshot(id: "msg_1", blocks: [.text("Selam", presentation: nil)]))
    }
    @Test func decodesResult() {
        let line = #"{"type":"result","subtype":"success","result":"Selam","total_cost_usd":0.01,"usage":{"output_tokens":5}}"#
        #expect(StreamJsonEvent.decode(line) == .turnResult(costUSD: 0.01, outputTokens: 5))
    }
    @Test func unknownAndGarbageAreIgnored() {
        #expect(StreamJsonEvent.decode(#"{"type":"rate_limit_event"}"#) == .rateLimit)
        #expect(StreamJsonEvent.decode(#"{"type":"system","subtype":"status"}"#) == .ignored)
        #expect(StreamJsonEvent.decode("yarım-json{") == .ignored)
        #expect(StreamJsonEvent.decode("") == .ignored)
    }
    /// Karar 104: `--replay-user-messages` yankısı `message.id` taşımaz —
    /// kimlik üst seviye `uuid`'den gelir (rastgele kimlik upsert'i bozardı).
    @Test func replayedUserMessageUsesTopLevelUUID() {
        let line = #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"selam"}]},"uuid":"u-42","isReplay":true}"#
        #expect(StreamJsonEvent.decode(line) == .userEcho(id: "u-42", blocks: [.text("selam", presentation: nil)]))
    }
}
