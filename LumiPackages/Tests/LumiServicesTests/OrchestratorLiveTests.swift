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

    /// Faz 3: onay beklerken araç çağrısı uzun süre açık kalır — Claude'un
    /// MCP zaman aşımına (`MCP_TOOL_TIMEOUT`) düşmemeli. Varsayılan bekleme
    /// 70 sn (`LUMI_LIVE_APPROVAL_DELAY` ile değişir).
    private struct SlowApproval: OrchestratorToolHandling {
        let delay: Duration
        func call(name: String, arguments: Data) async -> OrchestratorToolResult {
            switch name {
            case OrchestratorTools.listTerminals:
                return OrchestratorToolResult(text: #"{"terminals":[{"id":"t-1","title":"zebra-refactor","provider":"claude","status":"waiting"}]}"#)
            case OrchestratorTools.sendToTerminal:
                try? await Task.sleep(for: delay)
                return OrchestratorToolResult(text: "Sent to \"zebra-refactor\" (t-1).")
            default:
                return .failure("unexpected tool \(name)")
            }
        }
    }

    func testLongApprovalWaitDoesNotTimeOutTheToolCall() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["LUMI_LIVE_ORCHESTRATOR"] == "1" else {
            throw XCTSkip("canlı test: LUMI_LIVE_ORCHESTRATOR=1 ile koşar")
        }
        let delay = Duration.seconds(Int(env["LUMI_LIVE_APPROVAL_DELAY"] ?? "") ?? 70)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("orchestrator-live-\(UUID().uuidString)")
        let server = LumiMCPServer()
        let control = try await server.start(handler: SlowApproval(delay: delay))
        let service = OrchestratorService(workingDirectory: directory, environment: AgentChildEnvironment.cleaned())
        let run = try await service.start(OrchestratorLaunch(
            sessionID: UUID().uuidString.lowercased(), resume: false, control: control
        ))

        await service.send("Send the message 'run the tests' to the zebra-refactor terminal, then tell me the tool's exact result.")

        var final = ChatJournalState()
        for await state in run.updates {
            final = state
            if state.completedTurns >= 1 { break }
        }
        await service.stop()
        await server.stop()

        let results = final.messages.flatMap(\.blocks).compactMap { block -> (String, Bool)? in
            if case let .toolResult(output, isError) = block { return (output, isError) }
            return nil
        }
        XCTAssertTrue(results.contains { $0.0.contains("Sent to") && !$0.1 }, "araç sonucu dönmedi: \(results)")
    }

    /// Faz 4: gerçek haiku özeti JSON sözleşmesine uyuyor ve soruyu yakalıyor.
    func testHaikuDigestFollowsTheJSONContract() async throws {
        guard ProcessInfo.processInfo.environment["LUMI_LIVE_ORCHESTRATOR"] == "1" else {
            throw XCTSkip("canlı test: LUMI_LIVE_ORCHESTRATOR=1 ile koşar")
        }
        let message = """
        I refactored the authentication module: moved token refresh into `AuthSession`, \
        replaced the callback API with async/await, and updated 14 call sites. All 212 tests pass. \
        I also noticed the legacy `LoginViewController` still uses the old API, but changing it \
        touches the onboarding flow. Should I migrate `LoginViewController` too, or leave it for a \
        separate PR?
        """
        let digest = try await ClaudeDigestService().summarize(agentMessage: message, terminalTitle: "auth-refactor")
        XCTAssertFalse(digest.summary.isEmpty)
        XCTAssertTrue(digest.needsUser, "soru yakalanmadı: \(digest)")
        print("haiku digest:", digest.summary)
    }
}
