import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Karar 126: orchestrator ışık süzmeleri — yalnız görsel sinyal; okuma
/// araçları ve teslim edilen özetler hedeften orchestrator'a, yazma araçları
/// orchestrator'dan hedefe uçar.
@MainActor
final class OrchestratorFlightsTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_000)
    private var flights: OrchestratorFlights!
    private var service: FakeTerminalService!
    private var terminals: TerminalListStore!
    private var toolbox: OrchestratorToolbox!

    private let api = Repo(name: "api", path: "/p/api", isGitRepo: true, source: .standalone)

    override func setUp() async throws {
        flights = OrchestratorFlights(now: { [unowned self] in self.clock })
        let toasts = ToastStore(autoDismissAfter: 60)
        service = FakeTerminalService()
        terminals = TerminalListStore(service: service, toasts: toasts)
        let repos = RepoStore(service: FakeRepoService(repos: [api]))
        await repos.reload()
        let workspaces = ProjectWorkspaceStore(
            service: FakeWorkspaceService(), config: FakeConfigService(), repos: repos, toasts: toasts
        )
        workspaces.updateSidebarProjects([api.path])
        toolbox = OrchestratorToolbox(
            terminals: terminals, workspaces: workspaces, repos: repos,
            transcripts: FakeTerminalTranscripts(), screenText: { _ in "" },
            promptQueue: PromptQueueStore(service: service, toasts: toasts),
            trust: FakeClaudeWorkspaceTrust(), flights: flights
        )
    }

    @discardableResult
    private func agent(_ name: String, status: TerminalStatus = .waitingSeen, provider: AgentProvider? = .claude) -> TerminalMeta {
        let meta = TerminalMeta(id: TerminalID(), name: name, repoPath: api.path, createdAt: Date(),
                                status: status, provider: provider)
        terminals.apply(.spawned(meta))
        return meta
    }

    private func run(_ tool: String, _ args: [String: Any] = [:]) async -> OrchestratorToolResult {
        let data = try! JSONSerialization.data(withJSONObject: args)
        return await toolbox.call(name: tool, arguments: data)
    }

    private var trips: [OrchestratorFlights.Direction: [OrchestratorFlights.Endpoint]] {
        Dictionary(grouping: flights.active, by: \.direction).mapValues { $0.map(\.endpoint) }
    }

    // MARK: - Model

    func testLaunchDeduplicatesStaggersAndCaps() {
        let id = TerminalID()
        flights.launch(.inbound, [.terminal(id), .terminal(id), .project("/a")])
        XCTAssertEqual(flights.active.map(\.endpoint), [.terminal(id), .project("/a")])
        XCTAssertEqual(
            flights.active[1].startsAt.timeIntervalSince(flights.active[0].startsAt),
            OrchestratorFlights.stagger, accuracy: 0.0001
        )

        flights.launch(.inbound, (0..<20).map { .project("/p\($0)") })
        XCTAssertEqual(flights.active.count, 2 + OrchestratorFlights.maxPerLaunch)
    }

    func testDelayedLaunchStartsLaterAndExpiresAfterItsDuration() {
        flights.launch(.outbound, [.checkout("/p/api")], delay: 0.3)
        let flight = try! XCTUnwrap(flights.active.first)
        XCTAssertLessThan(flight.progress(at: clock), 0, "gecikmeli uçuş henüz kalkmadı")

        clock = flight.endsAt.addingTimeInterval(-0.01)
        flights.expire()
        XCTAssertEqual(flights.active.count, 1)
        clock = flight.endsAt
        flights.expire()
        XCTAssertTrue(flights.active.isEmpty)
    }

    func testActiveFlightsAreBounded() {
        for index in 0..<10 {
            flights.launch(.inbound, (0..<OrchestratorFlights.maxPerLaunch).map { .project("/\(index)/\($0)") })
        }
        XCTAssertEqual(flights.active.count, OrchestratorFlights.maxActive)
    }

    // MARK: - Araçlar

    func testListProjectsFliesFromEachProjectToTheOrchestrator() async {
        _ = await run(OrchestratorTools.listProjects)
        XCTAssertEqual(trips[.inbound], [.project(api.path)])
        XCTAssertNil(trips[.outbound])
    }

    func testListTerminalsFliesOnlyFromMatchingClaudeTerminals() async {
        let login = agent("login")
        agent("shell", provider: nil)
        agent("billing")

        _ = await run(OrchestratorTools.listTerminals, ["query": "login"])

        XCTAssertEqual(trips[.inbound], [.terminal(login.id)])
    }

    func testReadTerminalFliesFromTheTerminal() async {
        let meta = agent("login")
        _ = await run(OrchestratorTools.readTerminal, ["terminal_id": meta.id.description])
        XCTAssertEqual(trips[.inbound], [.terminal(meta.id)])
    }

    func testSendToTerminalFliesFromTheOrchestrator() async {
        let meta = agent("login")
        _ = await run(OrchestratorTools.sendToTerminal, ["terminal_id": meta.id.description, "message": "devam"])
        XCTAssertEqual(trips[.outbound], [.terminal(meta.id)])
    }

    func testStartTerminalFliesToTheNewTerminalAfterItIsLaidOut() async throws {
        let result = await run(OrchestratorTools.startTerminal, ["path": api.path])
        XCTAssertFalse(result.isError, result.text)
        let spawned = try XCTUnwrap(service.spawnedMetas.first)
        let flight = try XCTUnwrap(flights.active.first)
        XCTAssertEqual(flight.direction, .outbound)
        XCTAssertEqual(flight.endpoint, .terminal(spawned.id))
        XCTAssertEqual(flight.startsAt.timeIntervalSince(clock), OrchestratorToolbox.newTerminalFlightDelay, accuracy: 0.0001)
    }

    func testRejectedCallsDoNotFly() async {
        agent("shell", provider: nil)
        _ = await run(OrchestratorTools.sendToTerminal, ["terminal_id": "nope-nope", "message": "x"])
        _ = await run(OrchestratorTools.startTerminal, ["path": "/elsewhere"])
        _ = await run(OrchestratorTools.readTerminal, ["terminal_id": terminals.terminals[0].id.description])
        XCTAssertTrue(flights.active.isEmpty)
    }
}
