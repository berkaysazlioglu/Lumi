import XCTest
import LumiWire
@testable import LumiMobileKit

final class ChatTranscriptTests: XCTestCase {

    private func assistant(_ id: String, _ text: String) -> ChatMessage {
        ChatMessage(id: id, role: .assistant, blocks: [.text(text, presentation: nil)],
                    timestampMs: nil, turnId: nil)
    }
    private func user(_ id: String, _ text: String) -> ChatMessage {
        ChatMessage(id: id, role: .user, blocks: [.text(text, presentation: nil)],
                    timestampMs: nil, turnId: nil)
    }

    // MARK: Streaming gate

    /// While the response is streaming (not yet in the transcript) → text is visible.
    func testStreamingShowsWhileNoRealMessage() {
        var gate = ChatStreamGate()
        let prev = [assistant("a1", "previous response")]
        let (g1, s1) = chatDeriveStreaming(gate: gate, folded: prev, incoming: "Hell", streamLive: true)
        gate = g1
        XCTAssertEqual(s1, "Hell")
        let (g2, s2) = chatDeriveStreaming(gate: gate, folded: prev, incoming: "Hello world", streamLive: true)
        gate = g2
        XCTAssertEqual(s2, "Hello world")
    }

    /// When the real message lands in the transcript (tail text gets ahead + tail moved)
    /// → bubble is hidden (nil), real message stays. Mac sends append while status is still live.
    func testStreamingHidesWhenRealMessageLands() {
        var gate = ChatStreamGate()
        let prev = [assistant("a1", "previous")]
        let (g1, _) = chatDeriveStreaming(gate: gate, folded: prev, incoming: "Hello world", streamLive: true)
        gate = g1
        // Response landed (append), status still live: new assistant tail starts with the text.
        let landed = prev + [assistant("a2", "Hello world!")]
        let (g2, s2) = chatDeriveStreaming(gate: gate, folded: landed, incoming: "Hello world", streamLive: true)
        gate = g2
        XCTAssertNil(s2, "streaming bubble must be hidden when real message lands in the tail")
    }

    /// When the turn ends (streamLive=false → no preview) the bubble is hidden (orca). The real
    /// message is in the transcript at that moment (Mac sends append before setting status to nil)
    /// so there is no vanish — see AppModel integration test.
    func testStreamingHiddenWhenTurnEnds() {
        var gate = ChatStreamGate()
        let landed = [assistant("a1", "Answer complete")]
        let (g1, _) = chatDeriveStreaming(gate: gate, folded: landed, incoming: "Answ", streamLive: true)
        gate = g1
        let (g2, s2) = chatDeriveStreaming(gate: gate, folded: landed, incoming: nil, streamLive: false)
        gate = g2
        XCTAssertNil(s2, "bubble is hidden when turn ends")
    }

    /// A new segment (text that doesn't extend the previous response) re-anchors.
    func testNewSegmentReanchors() {
        var gate = ChatStreamGate()
        let base = [assistant("a1", "first")]
        let (g1, _) = chatDeriveStreaming(gate: gate, folded: base, incoming: "first response", streamLive: true)
        gate = g1
        let landed = base + [assistant("a2", "first response")]
        let (g2, s2) = chatDeriveStreaming(gate: gate, folded: landed, incoming: "first response", streamLive: true)
        gate = g2
        XCTAssertNil(s2)
        // New turn starts: different text → new bubble is visible.
        let (g3, s3) = chatDeriveStreaming(gate: gate, folded: landed, incoming: "second", streamLive: true)
        gate = g3
        XCTAssertEqual(s3, "second")
    }

    // MARK: pending echo

    func testPendingAppendComputesExpectedOccurrence() {
        var pend: [ChatPending] = []
        pend = chatPendingAppend(current: pend, id: "p1", text: "hello",
                                 baselineTailMessageId: "a1")
        XCTAssertEqual(pend.first?.expectedOccurrence, 1)
        // Send the same text again (not yet landed) → 2nd occurrence is expected.
        pend = chatPendingAppend(current: pend, id: "p2", text: "hello",
                                 baselineTailMessageId: "a1")
        XCTAssertEqual(pend.last?.expectedOccurrence, 2)
    }

    func testPendingRetiredWhenTranscriptEchoesText() {
        var pend = chatPendingAppend(current: [], id: "p1", text: "hello",
                                     baselineTailMessageId: "a1")
        // User "hello" appeared in the transcript → pending is retired.
        let msgs = [assistant("a1", "..."), user("u1", "hello")]
        pend = chatRetireLandedPending(messages: msgs, current: pend)
        XCTAssertTrue(pend.isEmpty, "pending must be removed when transcript echoes the text")
    }

    func testPendingKeptWhenNoTranscriptEcho() {
        // If stream-json does not echo the user message, the pending STAYS (persistent display).
        let pend = chatPendingAppend(current: [], id: "p1", text: "hello",
                                     baselineTailMessageId: "a1")
        let msgs = [assistant("a1", "response")]
        let after = chatRetireLandedPending(messages: msgs, current: pend)
        XCTAssertEqual(after.count, 1, "user message must remain on screen when there is no echo")
    }

    /// Decision 130: the count is relative to the baseline row — a snapshot that drops
    /// older copies of the same text (size cap) still retires the echo exactly once.
    func testPendingCountsOnlyEchoesAfterBaseline() {
        let history = [user("u1", "hello"), assistant("a1", "x"), user("u2", "hello"), assistant("a2", "y")]
        var pend = chatPendingAppend(current: [], id: "p1", text: "hello", baselineTailMessageId: "a2")
        pend = chatRetireLandedPending(messages: history, current: pend)
        XCTAssertEqual(pend.count, 1, "older copies before the baseline do not retire it")
        let truncatedWithEcho = [assistant("a2", "y"), user("u3", "hello")]
        XCTAssertTrue(chatRetireLandedPending(messages: truncatedWithEcho, current: pend).isEmpty)
    }

    // MARK: assemble

    func testAssembleAnchorsPendingAfterBaselineAndStreamingAtEnd() {
        let messages = [assistant("a1", "previous response")]
        let pending = [ChatPending(id: "p1", text: "my question", expectedOccurrence: 1,
                                   baselineTailMessageId: "a1")]
        let data = chatAssembleRenderMessages(messages: messages, pending: pending,
                                              streaming: "writing response")
        XCTAssertEqual(data.map(\.id), ["a1", "p1", "streaming"])
        XCTAssertEqual(data[1].role, .user)
        XCTAssertEqual(data[2].role, .assistant)
    }

    func testAssembleLeadingWhenNoBaselineAndTrailingWhenBaselineMissing() {
        // baseline nil → at the start
        let d1 = chatAssembleRenderMessages(messages: [], pending: [
            ChatPending(id: "p1", text: "first message", expectedOccurrence: 1, baselineTailMessageId: nil)
        ], streaming: nil)
        XCTAssertEqual(d1.map(\.id), ["p1"])
        // baseline message not in the list → at the end
        let d2 = chatAssembleRenderMessages(messages: [assistant("a1", "x")], pending: [
            ChatPending(id: "p2", text: "late", expectedOccurrence: 1, baselineTailMessageId: "missing")
        ], streaming: nil)
        XCTAssertEqual(d2.map(\.id), ["a1", "p2"])
    }
}
