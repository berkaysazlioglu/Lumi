import Testing
import Foundation
import LumiKit
@testable import LumiRemote

/// Karar 130: chat frame'leri relay'in 1 MB sınırının altında kalır.
@Suite struct ChatFrameBudgetTests {

    private func message(_ id: String, chars: Int) -> ChatMessage {
        ChatMessage(id: id, role: .assistant,
                    blocks: [.text(String(repeating: "a", count: chars), presentation: nil)],
                    timestampMs: nil, turnId: nil)
    }

    @Test func smallSnapshotPassesUnchanged() {
        let messages = (0..<5).map { message("m\($0)", chars: 100) }
        let fit = ChatFrameBudget.fitSnapshot(messages)
        #expect(fit.messages == messages)
        #expect(!fit.hasEarlier)
    }

    @Test func oversizedSnapshotKeepsNewestUnderBudget() {
        let messages = (0..<10).map { message("m\($0)", chars: 50_000) }
        let fit = ChatFrameBudget.fitSnapshot(messages, budget: 200_000)
        #expect(fit.hasEarlier)
        #expect(fit.messages.last?.id == "m9", "newest message is kept")
        #expect(fit.messages.map(\.id) == Array(messages.suffix(fit.messages.count)).map(\.id))
        let total = fit.messages.map(ChatFrameBudget.byteSize).reduce(0, +)
        #expect(total <= 200_000)
    }

    @Test func hugeBlockIsTruncatedKeepingId() {
        let clamped = ChatFrameBudget.clamp(message("big", chars: 2_000_000))
        #expect(clamped.id == "big")
        #expect(ChatFrameBudget.byteSize(clamped) < ChatFrameBudget.maxFrameBytes)
        guard case let .text(text, _) = clamped.blocks.first else { Issue.record("text block"); return }
        #expect(text.hasSuffix(ChatFrameBudget.truncationMarker))
    }

    @Test func appendSplitsIntoChunksUnderBudgetInOrder() {
        let messages = (0..<6).map { message("m\($0)", chars: 40_000) }
        let chunks = ChatFrameBudget.chunkAppend(messages, budget: 100_000)
        #expect(chunks.count > 1)
        #expect(chunks.flatMap { $0 }.map(\.id) == messages.map(\.id))
        for chunk in chunks {
            #expect(chunk.map(ChatFrameBudget.byteSize).reduce(0, +) <= 100_000)
        }
    }
}
