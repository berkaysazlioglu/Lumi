import Foundation
import LumiKit
import XCTest
@testable import LumiServices

/// Karar 103: gerçek `claude` + gerçek loopback MCP sunucusu ile uçtan uca
/// zincir. Token harcar ve ağ ister — yalnız `LUMI_LIVE_ORCHESTRATOR=1` ile koşar.
final class OrchestratorLiveTests: XCTestCase {
    private struct FixedTerminals: OrchestratorToolHandling {
        func call(name: String, arguments: Data) async -> OrchestratorToolResult {
            guard name == OrchestratorTools.listTerminals else { return .failure("unexpected tool \(name)") }
            return OrchestratorToolResult(text: #"{"terminals":[{"id":"t-1","title":"zebra-refactor","status":"needs-attention"}]}"#)
        }
    }

    func testOrchestratorCallsLumiToolOverMCP() async throws {
        guard ProcessInfo.processInfo.environment["LUMI_LIVE_ORCHESTRATOR"] == "1" else {
            throw XCTSkip("canlı test: LUMI_LIVE_ORCHESTRATOR=1 ile koşar")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("orchestrator-live-\(UUID().uuidString)")
        let server = LumiMCPServer()
        let control = try await server.start(handler: FixedTerminals())
        let service = OrchestratorService(workingDirectory: directory, environment: AgentChildEnvironment.cleaned())
        let run = try await service.start(OrchestratorLaunch(
            sessionID: UUID().uuidString.lowercased(), resume: false, control: control
        ))

        await service.send("Use list_terminals and tell me the exact title of the terminal that needs attention.")

        var final = ChatJournalState()
        let deadline = Date().addingTimeInterval(90)
        for await state in run.updates {
            final = state
            if state.completedTurns >= 1 || Date() > deadline { break }
        }
        await service.stop()
        await server.stop()

        let blocks = final.messages.flatMap(\.blocks)
        XCTAssertTrue(blocks.contains { block in
            if case let .toolCall(name, _, _) = block { return name == "mcp__lumi__list_terminals" }
            return false
        }, "araç çağrılmadı: \(final.messages)")
        let replies = final.messages.filter { $0.role == .assistant }.flatMap(\.blocks).compactMap { block -> String? in
            if case let .text(text, _) = block { return text }
            return nil
        }
        XCTAssertTrue(replies.joined().contains("zebra-refactor"), "cevap araç çıktısını kullanmadı: \(replies)")
    }
}
