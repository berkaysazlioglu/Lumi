import Foundation

/// The plain-text prose of a folded turn's owner message: `.text` blocks joined
/// with newlines, tool blocks skipped. `nil` when the result is effectively empty
/// (e.g. a tool-only turn) so callers can hide the copy affordance.
public func chatCopyText(_ turn: FoldedTurn) -> String? {
    let parts = turn.message.blocks.compactMap { block -> String? in
        if case let .text(text, _) = block { return text }
        return nil
    }
    let joined = parts.joined(separator: "\n")
    return joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : joined
}
