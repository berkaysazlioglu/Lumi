import Foundation

/// A folded turn: one "owner" message plus its tool-only activity messages.
public struct FoldedTurn: Identifiable, Sendable, Equatable {
    public let id: String
    public let message: ChatMessage
    public let toolActivity: [ChatMessage]

    public init(id: String, message: ChatMessage, toolActivity: [ChatMessage]) {
        self.id = id
        self.message = message
        self.toolActivity = toolActivity
    }
}

/// Folds tool-only messages (containing only tool-call/tool-result blocks) into the
/// preceding text turn. If there is no preceding owner, they become their own turn
/// (orca fold subset).
public func foldChatMessages(_ messages: [ChatMessage]) -> [FoldedTurn] {
    var result: [FoldedTurn] = []
    for message in messages {
        if isToolOnly(message), var last = result.last {
            last = FoldedTurn(id: last.id, message: last.message,
                              toolActivity: last.toolActivity + [message])
            result[result.count - 1] = last
        } else {
            result.append(FoldedTurn(id: message.id, message: message, toolActivity: []))
        }
    }
    return result
}

private func isToolOnly(_ message: ChatMessage) -> Bool {
    guard !message.blocks.isEmpty else { return false }
    return message.blocks.allSatisfy { block in
        switch block {
        case .toolCall, .toolResult: return true
        default: return false
        }
    }
}
