import Foundation
import LumiWire

// Swift port of orca's mobile chat render logic (source:
// orca `mobile/src/session/mobile-native-chat-{streaming-gate,pending-echo,
// pending-retirement,render-data}.ts`). Faithfully replicates two behaviors:
//   1. Live streaming text is NOT REMOVED FROM THE SCREEN when a turn ends — it
//      stays as a synthetic bubble until the real transcript message lands (orca
//      "caught-up" gate). Even if the Mac sets streamingText to null, the phone
//      HOLDS the text and hides it only when the transcript tail text "gets ahead."
//   2. The user's own sent message appears IMMEDIATELY (optimistic echo,
//      client-side; no server acknowledgment is waited for). When the transcript
//      echoes the text (if it does), it is retired via count-based dedup.
// Orca's image/multi-tab/glue-run edge cases are out of scope for this phase
// (single session, no images) — intentionally not ported.

// MARK: - Text normalization (orca normalizeReconcileText / normalizedUserText)

/// Drops control characters, trims, and collapses consecutive whitespace to a single space.
public func normalizeChatUserText(_ text: String) -> String {
    let noControls = String(text.unicodeScalars.filter { scalar in
        // Drop ANSI/terminal control characters (C0, DEL); \n \t fold into normal space.
        scalar.value >= 0x20 || scalar == " " || scalar == "\n" || scalar == "\t"
    })
    let parts = noControls.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" })
    return parts.joined(separator: " ")
}

/// Normalized text of a user message (assistant/other → nil).
public func normalizedChatUserText(_ message: ChatMessage) -> String? {
    guard message.role == .user else { return nil }
    let joined = message.blocks.compactMap { block -> String? in
        if case .text(let t, _) = block { return t } else { return nil }
    }.joined(separator: " ")
    let n = normalizeChatUserText(joined)
    return n.isEmpty ? nil : n
}

// MARK: - Optimistic pending echo (orca pending-echo + pending-retirement)

/// A user message echo appended to the list without waiting for server acknowledgment.
public struct ChatPending: Identifiable, Sendable, Equatable {
    public let id: String
    public let text: String
    /// Which occurrence of this text after `baselineTailMessageId` triggers retirement.
    public let expectedOccurrence: Int
    /// The transcript tail message id at send time (the echo is drawn after this row).
    public let baselineTailMessageId: String?

    public init(id: String, text: String, expectedOccurrence: Int, baselineTailMessageId: String?) {
        self.id = id
        self.text = text
        self.expectedOccurrence = expectedOccurrence
        self.baselineTailMessageId = baselineTailMessageId
    }
}

/// Appends a new pending. `expectedOccurrence` counts echoes AFTER the baseline tail
/// row: outstanding same-text echoes + 1 (decision 130 — relative to the baseline so
/// a snapshot that drops old rows can neither retire it early nor keep it forever).
public func chatPendingAppend(current: [ChatPending], id: String, text: String,
                              baselineTailMessageId: String?) -> [ChatPending] {
    let normalized = normalizeChatUserText(text)
    let earlierOutstanding = current.filter { normalizeChatUserText($0.text) == normalized }.count
    return current + [ChatPending(id: id, text: text, expectedOccurrence: earlierOutstanding + 1,
                                  baselineTailMessageId: baselineTailMessageId)]
}

/// Retires a pending once its text appeared `expectedOccurrence` times after its baseline
/// row (orca exact-landing count pass). A baseline that is absent (empty chat at send
/// time, or a replaced transcript after `/clear`) counts the whole list.
/// Glue-run/image branches not ported.
public func chatRetireLandedPending(messages: [ChatMessage], current: [ChatPending]) -> [ChatPending] {
    var indexById: [String: Int] = [:]
    for (index, message) in messages.enumerated() where indexById[message.id] == nil {
        indexById[message.id] = index
    }
    return current.filter { p in
        let n = normalizeChatUserText(p.text)
        if n.isEmpty { return true }
        let start = p.baselineTailMessageId.flatMap { indexById[$0] }.map { $0 + 1 } ?? 0
        let landed = messages[start...].reduce(0) { normalizedChatUserText($1) == n ? $0 + 1 : $0 }
        return landed < p.expectedOccurrence
    }
}

// MARK: - Streaming gate (orca deriveMobileNativeChatStreaming + hold adaptation)

/// Streaming bubble gate (exact port of orca deriveMobileNativeChatStreaming).
/// The bubble is hidden only when the transcript tail text "gets ahead AND has moved
/// since the segment start" (caughtUp = real response landed); a new response that
/// repeats the prefix of an older identical turn is not accidentally hidden
/// (baselineTailId guard). When the turn ends (streamLive=false → incoming nil) the
/// bubble is hidden — the real message is in the transcript at that moment (Mac sends
/// the append BEFORE setting status to nil) → no gap/vanish.
public struct ChatStreamGate: Sendable, Equatable {
    public var prevText: String
    public var baselineTailId: String?
    public init(prevText: String = "", baselineTailId: String? = nil) {
        self.prevText = prevText
        self.baselineTailId = baselineTailId
    }
}

private func assistantTailText(_ tail: ChatMessage?) -> String {
    guard let tail, tail.role == .assistant else { return "" }
    return tail.blocks.compactMap { block -> String? in
        if case .text(let t, _) = block { return t } else { return nil }
    }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Advances the gate by one tick and returns the visible streaming text (nil = hide).
/// `folded`: folded journal messages. `incoming`: streaming text at this tick
/// (nil when turn is not live → "no observation"). `streamLive`: is the agent still in a turn?
public func chatDeriveStreaming(gate: ChatStreamGate, folded: [ChatMessage],
                                incoming: String?, streamLive: Bool)
    -> (gate: ChatStreamGate, streaming: String?) {
    var g = gate
    let text = (incoming ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let tailId = folded.last?.id
    if text.isEmpty {
        // Empty-text tick: anchor the tail as reliable history only when outside a turn
        // (or when the gate has never been anchored); skip anchoring mid-turn so a new
        // response is not drawn as a bubble a second time.
        let canAnchor = tailId != nil && (!streamLive || g.baselineTailId == nil)
        if canAnchor { g.prevText = ""; g.baselineTailId = tailId }
        return (g, nil)
    }
    // Not extending prevText → new segment (new response chunk) → re-anchor the tail.
    let segmentStart = !g.prevText.isEmpty && !text.hasPrefix(g.prevText)
    let baseline = segmentStart ? tailId : g.baselineTailId
    let tailLeads = assistantTailText(folded.last).hasPrefix(text)
    let caughtUp = tailLeads && tailId != baseline
    g.prevText = text
    g.baselineTailId = baseline
    return (g, caughtUp ? nil : text)
}

// MARK: - Render list assembly (orca buildMobileNativeChatTransientData)

/// leading pending + (journal messages, each followed by its anchored pending) +
/// streaming bubble + trailing pending. Synthetic messages are also normal ChatMessage
/// values, so the caller folds the result with `foldChatMessages` into turns.
public func chatAssembleRenderMessages(messages: [ChatMessage], pending: [ChatPending],
                                       streaming: String?) -> [ChatMessage] {
    let ids = Set(messages.map { $0.id })
    var leading: [ChatMessage] = []
    var trailing: [ChatMessage] = []
    var anchored: [String: [ChatMessage]] = [:]
    for p in pending {
        let bubble = ChatMessage(id: p.id, role: .user,
                                 blocks: [.text(p.text, presentation: nil)],
                                 timestampMs: nil, turnId: nil)
        if let base = p.baselineTailMessageId {
            if ids.contains(base) { anchored[base, default: []].append(bubble) }
            else { trailing.append(bubble) }   // row not yet arrived / folded → at end (position preserved)
        } else {
            leading.append(bubble)             // sent to empty chat → at the start
        }
    }
    var result: [ChatMessage] = leading
    for m in messages {
        result.append(m)
        if let attached = anchored[m.id] { result.append(contentsOf: attached) }
    }
    if let s = streaming, !s.isEmpty {
        result.append(ChatMessage(id: "streaming", role: .assistant,
                                  blocks: [.text(s, presentation: nil)],
                                  timestampMs: nil, turnId: nil))
    }
    result.append(contentsOf: trailing)
    return result
}
