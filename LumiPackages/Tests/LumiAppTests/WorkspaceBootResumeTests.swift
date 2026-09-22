import Foundation
import LumiKit
import LumiState
import LumiTestSupport
import XCTest
@testable import LumiAppCore

@MainActor
final class WorkspaceBootResumeTests: XCTestCase {
    func testCapturesClaudeAndCodexWithOriginHome() {
        let claude = TerminalMeta(
            id: TerminalID(),
            name: "Claude",
            repoPath: "/repo/claude",
            createdAt: .distantPast,
            claudeSessionID: "11111111-2222-3333-4444-555555555555",
            provider: .claude
        )
        let codex = TerminalMeta(
            id: TerminalID(),
            name: "Codex",
            repoPath: "/repo/codex",
            createdAt: .distantPast,
            codexSessionID: "thread-123",
            codexHome: "/Users/dev/.codex",
            provider: .codex
        )

        XCTAssertEqual(WorkspaceBootAssembly.resumeSessions(from: [claude, codex]), [
            ResumeSession(
                repoPath: "/repo/claude",
                sessionID: "11111111-2222-3333-4444-555555555555"
            ),
            ResumeSession(
                repoPath: "/repo/codex",
                sessionID: "thread-123",
                provider: .codex,
                codexHome: "/Users/dev/.codex"
            ),
        ])
    }

    func testDoesNotPersistCodexWithoutAuthoritativeHookThread() {
        let codex = TerminalMeta(
            id: TerminalID(),
            name: "Codex",
            repoPath: "/repo",
            createdAt: .distantPast,
            codexHome: "/Users/dev/.codex",
            provider: .codex
        )
        XCTAssertTrue(WorkspaceBootAssembly.resumeSessions(from: [codex]).isEmpty)
    }

    // MARK: - Karar 90: crash checkpoint'i

    private func makeHarness(
        seed: UIState = .defaults,
        openTabs: [String] = []
    ) async -> (FakeServiceRegistry, SharedStores, WorkspaceBootAssembly) {
        let registry = FakeServiceRegistry()
        await registry.fakeConfig.seed(seed)
        let shared = SharedStores.make(
            config: registry.config, terminal: registry.terminal, toastAutoDismissAfter: 60
        )
        openTabs.forEach { shared.navigation.openTab($0) }
        let assembly = WorkspaceBootAssembly()
        assembly.build(services: registry, shared: shared)
        return (registry, shared, assembly)
    }

    /// Config fake'i actor: koşul yerine "beklenen listeye ulaştı mı" yoklanır.
    private func resumeSessions(
        of registry: FakeServiceRegistry,
        until expected: [ResumeSession]
    ) async -> [ResumeSession] {
        let deadline = ContinuousClock.now + .seconds(2)
        var current = await registry.fakeConfig.uiState().resumeSessions
        while current != expected, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
            current = await registry.fakeConfig.uiState().resumeSessions
        }
        return current
    }

    private func claudeEntry(_ meta: TerminalMeta) -> ResumeSession {
        ResumeSession(repoPath: meta.repoPath, sessionID: meta.claudeSessionID!)
    }

    func testStartResumesOpenTabsThenRewritesSnapshotFromLiveTerminals() async {
        var stale = UIState.defaults
        stale.resumeSessions = [
            ResumeSession(repoPath: "/r/open", sessionID: "aaaaaaaa-0000-0000-0000-000000000001"),
            ResumeSession(repoPath: "/r/closed", sessionID: "aaaaaaaa-0000-0000-0000-000000000002"),
        ]
        let (registry, _, assembly) = await makeHarness(seed: stale, openTabs: ["/r/open"])
        defer { registry.removeTemporaryDirectories() }

        await assembly.start()

        // Yalnız açık tab'daki kayıt spawn edilir; liste "boşalt" yerine canlı
        // terminallerden yeniden üretilir — kapalı repo'nun kaydı düşer.
        XCTAssertEqual(registry.fakeTerminal.spawnCalls.map(\.repoPath), ["/r/open"])
        let live = registry.fakeTerminal.spawnedMetas
        XCTAssertEqual(live.count, 1)
        let written = await registry.fakeConfig.uiState().resumeSessions
        XCTAssertEqual(written, live.map(claudeEntry))
        await assembly.shutdown()
    }

    func testSpawnAfterStartCheckpointsWithoutQuit() async throws {
        let (registry, _, assembly) = await makeHarness()
        defer { registry.removeTemporaryDirectories() }
        await assembly.start()

        let meta = try registry.fakeTerminal.spawn(repoPath: "/r/a", task: nil, command: "claude")

        let written = await resumeSessions(of: registry, until: [claudeEntry(meta)])
        XCTAssertEqual(written, [claudeEntry(meta)], "spawn sonrası resumeSessions yazılmalı")
        await assembly.shutdown()
    }

    func testCodexSessionIDChangedCheckpointsThreadWithHome() async throws {
        let (registry, _, assembly) = await makeHarness()
        defer { registry.removeTemporaryDirectories() }
        await assembly.start()
        let spawned = try registry.fakeTerminal.spawn(repoPath: "/r/c", task: nil, command: "codex")
        _ = await resumeSessions(of: registry, until: [claudeEntry(spawned)])

        // Hook'tan thread kimliği geldi: servis meta'sı güncellenir + event yayınlanır.
        registry.fakeTerminal.replaceSpawnedMeta(TerminalMeta(
            id: spawned.id, name: spawned.name, repoPath: "/r/c", createdAt: spawned.createdAt,
            codexSessionID: "thread-9", codexHome: "/Users/dev/.codex", provider: .codex
        ))
        registry.fakeTerminal.emit(.codexSessionIDChanged(spawned.id, "thread-9"))

        let expected = [ResumeSession(
            repoPath: "/r/c", sessionID: "thread-9", provider: .codex, codexHome: "/Users/dev/.codex"
        )]
        let written = await resumeSessions(of: registry, until: expected)
        XCTAssertEqual(written, expected, "codex thread kimliği checkpoint'e yazılmalı")
        await assembly.shutdown()
    }

    func testExitedCheckpointsRemovalAndShutdownStopsListening() async throws {
        let (registry, _, assembly) = await makeHarness()
        defer { registry.removeTemporaryDirectories() }
        await assembly.start()
        let first = try registry.fakeTerminal.spawn(repoPath: "/r/a", task: nil, command: "claude")
        let second = try registry.fakeTerminal.spawn(repoPath: "/r/b", task: nil, command: "claude")
        _ = await resumeSessions(of: registry, until: [first, second].map(claudeEntry))

        // Kullanıcı terminali kapattı: kayıt düşer.
        registry.fakeTerminal.removeSpawnedMeta(first.id)
        registry.fakeTerminal.emit(.exited(first.id, code: 0))
        let afterExit = await resumeSessions(of: registry, until: [claudeEntry(second)])
        XCTAssertEqual(afterExit, [claudeEntry(second)], "exited sonrası kayıt düşmeli")

        // Kapanış: tüketici susar; killAll'ın .exited'ları son snapshot'ı ezemez.
        await assembly.shutdown()
        let updatesAtShutdown = await registry.fakeConfig.uiStateUpdateCount
        registry.fakeTerminal.removeSpawnedMeta(second.id)
        registry.fakeTerminal.emit(.exited(second.id, code: 0))
        try await Task.sleep(for: .milliseconds(50))
        let updatesAfter = await registry.fakeConfig.uiStateUpdateCount
        XCTAssertEqual(updatesAfter, updatesAtShutdown)
        let final = await registry.fakeConfig.uiState().resumeSessions
        XCTAssertEqual(final, [claudeEntry(second)])
    }

    func testAffectsResumeSessionsOnlyForMembershipEvents() {
        let id = TerminalID()
        XCTAssertTrue(WorkspaceBootAssembly.affectsResumeSessions(.exited(id, code: 0)))
        XCTAssertTrue(WorkspaceBootAssembly.affectsResumeSessions(.codexSessionIDChanged(id, "t")))
        XCTAssertFalse(WorkspaceBootAssembly.affectsResumeSessions(.statusChanged(id, .idle)))
        XCTAssertFalse(WorkspaceBootAssembly.affectsResumeSessions(.bell(id)))
    }
}
