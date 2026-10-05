import Testing
import Foundation
import LumiWire
@testable import LumiKit

@Suite struct ChatJournalTests {
    @Test func streamingTextAccumulatesThenClearsOnSnapshot() {
        let j = ChatJournal()
        _ = j.reduce(.systemInit(sessionID: "S1", cwd: "/repo"))
        _ = j.reduce(.streamTextDelta("Hel"))
        _ = j.reduce(.streamTextDelta("lo"))
        #expect(j.state.streamingText == "Hello")
        #expect(j.state.turnActive == true)
        _ = j.reduce(.assistantSnapshot(id: "msg_1", blocks: [.text("Hello", presentation: nil)]))
        // Tamamlanmış mesaj streaming'i geçince overlay düşer:
        #expect(j.state.streamingText == nil)
        #expect(j.state.messages.count == 1)
        #expect(j.state.messages[0].id == "msg_1")
        #expect(j.state.messages[0].role == .assistant)
    }
    @Test func snapshotUpsertsByIdNoDuplicate() {
        let j = ChatJournal()
        _ = j.reduce(.assistantSnapshot(id: "msg_1", blocks: [.text("a", presentation: nil)]))
        _ = j.reduce(.assistantSnapshot(id: "msg_1", blocks: [.text("a", presentation: nil), .toolCall(name: "Bash", inputPreview: "command=ls", state: "completed")]))
        #expect(j.state.messages.count == 1)             // aynı id → upsert
        #expect(j.state.messages[0].blocks.count == 2)
    }
    @Test func userEchoAppends() {
        let j = ChatJournal()
        _ = j.reduce(.userEcho(id: "u1", blocks: [.text("merhaba", presentation: nil)]))
        #expect(j.state.messages.count == 1)
        #expect(j.state.messages[0].role == .user)
    }
    @Test func resultEndsTurn() {
        let j = ChatJournal()
        _ = j.reduce(.streamTextDelta("x"))
        #expect(j.state.turnActive == true)
        _ = j.reduce(.turnResult(costUSD: 0.02, outputTokens: 5))
        #expect(j.state.turnActive == false)
        #expect(j.state.lastCostUSD == 0.02)
    }
    /// Karar 114: biten turn'ler sayılır — `turnActive` ilk delta'ya kadar
    /// false kaldığı için "cevap geldi mi?" sayaçla cevaplanır.
    @Test func turnResultsAreCounted() {
        let j = ChatJournal()
        #expect(j.state.completedTurns == 0)
        _ = j.reduce(.turnResult(costUSD: nil, outputTokens: nil))
        _ = j.reduce(.turnResult(costUSD: nil, outputTokens: nil))
        #expect(j.state.completedTurns == 2)
    }
}
