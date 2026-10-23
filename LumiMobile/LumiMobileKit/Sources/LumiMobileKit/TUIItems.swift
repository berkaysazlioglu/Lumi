import Foundation
import LumiWire

/// One line group of the Claude-TUI-style transcript.
public enum TUIItem: Sendable, Equatable {
    /// `> prompt`
    case user(String)
    /// `⏺ prose` (markdown)
    case assistant(String)
    /// `⏺ Name(preview)` + `⎿ output`; `result == nil` while it runs.
    case tool(name: String, preview: String, result: TUIToolResult?)
    /// Sub-agent spawn: `⏺ label · state`
    case subagent(label: String, state: String)
}

public struct TUIToolResult: Sendable, Equatable {
    public let output: String
    public let isError: Bool

    public init(output: String, isError: Bool) {
        self.output = output
        self.isError = isError
    }
}

/// Flattens a folded turn (owner message + its tool-only activity) into TUI
/// items in transcript order. A tool result attaches to the oldest tool call
/// still waiting for one — results arrive in a later message than their call.
public func tuiItems(for turn: FoldedTurn) -> [TUIItem] {
    var items: [TUIItem] = []
    var openTools: [Int] = []
    for message in [turn.message] + turn.toolActivity {
        for block in message.blocks {
            switch block {
            case let .text(text, _):
                items.append(message.role == .user ? .user(text) : .assistant(text))
            case let .toolCall(name, preview, _):
                openTools.append(items.count)
                items.append(.tool(name: name, preview: preview, result: nil))
            case let .toolResult(output, isError):
                attach(TUIToolResult(output: output, isError: isError), to: &items, open: &openTools)
            case let .subagentGroup(_, agents):
                items += agents.map { .subagent(label: $0.label, state: $0.state) }
            case .imageRef, .unknown:
                continue
            }
        }
    }
    return items
}

private func attach(_ result: TUIToolResult, to items: inout [TUIItem], open: inout [Int]) {
    guard !open.isEmpty else {
        // Orphan result (its call was folded into an earlier turn): show it bare.
        items.append(.tool(name: "", preview: "", result: result))
        return
    }
    let index = open.removeFirst()
    if case let .tool(name, preview, nil) = items[index] {
        items[index] = .tool(name: name, preview: preview, result: result)
    }
}
