import Foundation
import LumiWire

/// Stream-json event akışını, mevcut wire tipleriyle (Faz 2 wire'ı yeniden
/// kullansın) uyumlu bir duruma katlayan saf reducer (spec 2026-09-17 Faz 1 §C).
public struct ChatJournalState: Equatable, Sendable {
    public var messages: [ChatMessage]
    public var streamingText: String?
    public var turnActive: Bool
    public var lastCostUSD: Double?
    /// Biten turn sayısı (`result` olayları). `turnActive` ilk metin
    /// delta'sına kadar `false` kalır; "gönderilen mesaja cevap geldi mi?"
    /// sorusu bu sayaçla cevaplanır (karar 103).
    public var completedTurns: Int
    public init() {
        messages = []; streamingText = nil; turnActive = false; lastCostUSD = nil; completedTurns = 0
    }
}

public final class ChatJournal {
    public private(set) var state = ChatJournalState()
    public init() {}

    @discardableResult
    public func reduce(_ event: StreamJsonEvent) -> ChatJournalState {
        switch event {
        case .systemInit:
            break
        case let .streamTextDelta(text):
            state.turnActive = true
            state.streamingText = (state.streamingText ?? "") + text
        case let .assistantSnapshot(id, blocks):
            upsert(ChatMessage(id: id, role: .assistant, blocks: blocks, timestampMs: nil, turnId: id))
            // Tamamlanmış assistant mesajı canlı overlay'i süpürür (orca gate mantığı).
            state.streamingText = nil
        case let .userEcho(id, blocks):
            upsert(ChatMessage(id: id, role: .user, blocks: blocks, timestampMs: nil, turnId: id))
        case let .turnResult(cost, _):
            state.turnActive = false
            state.streamingText = nil
            state.completedTurns += 1
            if let cost { state.lastCostUSD = cost }
        case .rateLimit, .ignored:
            break
        }
        return state
    }

    private func upsert(_ message: ChatMessage) {
        if let idx = state.messages.firstIndex(where: { $0.id == message.id }) {
            state.messages[idx] = message
        } else {
            state.messages.append(message)
        }
    }
}
