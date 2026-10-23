import CoreGraphics
import LumiWire

/// A rendered turn's vertical extent in the chat ScrollView's named coordinate
/// space: 0 is the viewport's top edge, negative values have scrolled above it.
public struct ChatTurnFrame: Sendable, Equatable {
    public let minY: CGFloat
    public let maxY: CGFloat

    public init(minY: CGFloat, maxY: CGFloat) {
        self.minY = minY
        self.maxY = maxY
    }
}

/// Decision 131 (Claude Code fullscreen parity): the prompt the sticky header shows —
/// the most recent user prompt whose top has scrolled above the viewport, i.e. the
/// prompt the topmost visible text answers. `frames` holds only realized turns (the
/// list is lazy); turns above the topmost visible one are found by index, not frame.
/// `topInset` is the header's own height: a prompt under it counts as scrolled above,
/// so jumping to a prompt (top-anchored) leaves the header naming that prompt.
public func chatStickyPromptId(turns: [FoldedTurn], frames: [String: ChatTurnFrame],
                               topInset: CGFloat = 0) -> String? {
    guard let top = turns.firstIndex(where: { (frames[$0.id]?.maxY ?? -.infinity) > topInset }) else { return nil }
    if turns[top].message.role == .user, let frame = frames[turns[top].id], frame.minY < topInset {
        return turns[top].id
    }
    return turns[..<top].last(where: { $0.message.role == .user })?.id
}

/// Decision 131: the jump-to-bottom button's count — turns that arrived after the
/// user scrolled away from the bottom (`countWhenLeft` = turn count at that moment).
public func chatNewTurnCount(current: Int, countWhenLeft: Int?) -> Int {
    guard let countWhenLeft else { return 0 }
    return max(0, current - countWhenLeft)
}
