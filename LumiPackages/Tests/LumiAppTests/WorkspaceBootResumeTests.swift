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

    // MARK: - Karar 108: serbest terminallerin resume'u

    func testResumableKeepsOpenTabsAndExistingLooseDirectories() {
        let entries = ["/r/open", "/r/project-closed", "/loose/here", "/loose/gone"].enumerated().map {
            ResumeSession(repoPath: $1, sessionID: "aaaaaaaa-0000-0000-0000-00000000000\($0)")
        }
        let resumable = WorkspaceBootAssembly.resumableEntries(
            entries,
            isOpenTab: { $0 == "/r/open" },
            isLoose: { $0.hasPrefix("/loose") },
            directoryExists: { $0 == "/loose/here" }
        )
        XCTAssertEqual(resumable.map(\.repoPath), ["/r/open", "/loose/here"])
    }

    func testStartResumesLooseSessionInExistingDirectory() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("loose-resume-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var seed = UIState.defaults
        seed.resumeSessions = [
            ResumeSession(repoPath: dir.path, sessionID: "aaaaaaaa-0000-0000-0000-000000000003"),
        ]
        let (registry, shared, assembly) = await makeHarness(seed: seed)
        defer { registry.removeTemporaryDirectories() }

        await assembly.start()

        XCTAssertEqual(registry.fakeTerminal.spawnCalls.map(\.repoPath), [dir.path])
        XCTAssertTrue(shared.navigation.openTabs.isEmpty, "serbest resume repo tab'ı açmamalı")
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

    // Karar 94: `/clear` sonrası resume listesi yeni konuşmayı taşır — açılışta
    // `/clear` öncesi sohbet geri gelmez.
    func testClaudeSessionIDChangedCheckpointsNewConversation() async throws {
        let (registry, _, assembly) = await makeHarness()
        defer { registry.removeTemporaryDirectories() }
        await assembly.start()
        let spawned = try registry.fakeTerminal.spawn(repoPath: "/r/a", task: nil, command: "claude")
        _ = await resumeSessions(of: registry, until: [claudeEntry(spawned)])

        var cleared = spawned
        cleared.claudeSessionID = "after-clear"
        registry.fakeTerminal.replaceSpawnedMeta(cleared)
        registry.fakeTerminal.emit(.claudeSessionIDChanged(spawned.id, "after-clear"))

        let expected = [ResumeSession(repoPath: "/r/a", sessionID: "after-clear")]
        let written = await resumeSessions(of: registry, until: expected)
        XCTAssertEqual(written, expected, "/clear sonrası kimlik checkpoint'e yazılmalı")
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
        XCTAssertTrue(WorkspaceBootAssembly.affectsResumeSessions(.claudeSessionIDChanged(id, "c")))
        XCTAssertFalse(WorkspaceBootAssembly.affectsResumeSessions(.statusChanged(id, .idle)))
        XCTAssertFalse(WorkspaceBootAssembly.affectsResumeSessions(.bell(id)))
    }

    // MARK: - Karar 97: elle sıralama resume sırasına iner

    private func meta(_ name: String) -> TerminalMeta {
        TerminalMeta(id: TerminalID(), name: name, repoPath: "/repo", createdAt: .distantPast)
    }

    func testInDisplayOrderFollowsStoreOrder() {
        let (a, b, c) = (meta("a"), meta("b"), meta("c"))
        let ordered = WorkspaceBootAssembly.inDisplayOrder([a, b, c], order: [c, a, b])
        XCTAssertEqual(ordered.map(\.id), [c.id, a.id, b.id])
    }

    func testInDisplayOrderAppendsTerminalsNotYetInStore() {
        let (a, b, fresh) = (meta("a"), meta("b"), meta("fresh"))
        let ordered = WorkspaceBootAssembly.inDisplayOrder([a, fresh, b], order: [b, a])
        XCTAssertEqual(ordered.map(\.id), [b.id, a.id, fresh.id])
    }

    func testInDisplayOrderDropsTerminalsGoneFromService() {
        let (a, gone) = (meta("a"), meta("gone"))
        let ordered = WorkspaceBootAssembly.inDisplayOrder([a], order: [gone, a])
        XCTAssertEqual(ordered.map(\.id), [a.id])
    }
}
