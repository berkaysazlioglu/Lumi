import XCTest
@testable import LumiTerminal

/// Entegrasyon: spawn(command:) launch komutu GERÇEK login shell'de,
/// LaunchCommandGate'ten geçerek çalışır (karar 23 saha düzeltmesi).
@MainActor
final class TerminalSessionManagerSpawnTests: XCTestCase {
    func testLaunchCommandExecutesInRealShellAfterGate() async throws {
        // Arrange
        let manager = TerminalSessionManager()
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumi-gate-marker-\(UUID().uuidString)")
        defer {
            manager.killAll()
            try? FileManager.default.removeItem(at: marker)
        }

        // Act — gate: shell çıktısı + sessizlik penceresi sonrası komut yazılır
        let meta = try manager.spawn(
            repoPath: FileManager.default.temporaryDirectory.path,
            task: nil,
            command: "touch \(marker.path)"
        )

        // Assert — claude olmayan komuta session-id enjekte edilmez
        XCTAssertNil(meta.claudeSessionID)

        // Assert — komut shell'e ulaşıp çalıştı (login shell init'i dahil ≤10s)
        let deadline = ContinuousClock.now + .seconds(10)
        while !FileManager.default.fileExists(atPath: marker.path),
              ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: marker.path),
            "launch komutu gate'ten geçip shell'de çalışmalıydı"
        )
    }

    /// Karar 142: açık modların klasörleri spawn'ın shell'ine ulaşır.
    func testSpawnExportsClaudePluginDirectoriesToShell() async throws {
        let manager = TerminalSessionManager()
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumi-plugin-dirs-\(UUID().uuidString)")
        defer {
            manager.killAll()
            try? FileManager.default.removeItem(at: marker)
        }
        manager.setClaudePluginDirectories(["/m/a", "/m/b"])

        _ = try manager.spawn(
            repoPath: FileManager.default.temporaryDirectory.path,
            task: nil,
            command: "printenv CLAUDE_CODE_PLUGIN_DIRS > \(marker.path)"
        )

        let deadline = ContinuousClock.now + .seconds(10)
        while (try? String(contentsOf: marker, encoding: .utf8))?.isEmpty ?? true,
              ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(try? String(contentsOf: marker, encoding: .utf8), "/m/a:/m/b\n")
    }

    func testClaudeSpawnCarriesInjectedSessionID() async throws {
        // Arrange — komut yazımını görmek için marker'lı sahte claude komutu
        // kullanılamaz (ilk token claude olmalı); yalnız meta enjeksiyonu doğrulanır.
        let manager = TerminalSessionManager()
        defer { manager.killAll() }

        // Act
        let meta = try manager.spawn(
            repoPath: FileManager.default.temporaryDirectory.path,
            task: nil,
            command: "claude"
        )

        // Assert — meta, launch komutuna enjekte edilen UUID'yi taşır
        let id = try XCTUnwrap(meta.claudeSessionID)
        XCTAssertNotNil(UUID(uuidString: id))
    }

    func testCodexSpawnCarriesSelectedHomeAndResumedThread() throws {
        let manager = TerminalSessionManager()
        defer { manager.killAll() }
        manager.setLaunchEnvironment(["CODEX_HOME": "/tmp/selected-home"], for: .codex)

        let meta = try manager.spawn(
            repoPath: FileManager.default.temporaryDirectory.path,
            task: nil,
            command: "codex resume 'thread-123' || codex",
            environment: ["CODEX_HOME": "/tmp/original-home"]
        )

        XCTAssertEqual(meta.provider, .codex)
        XCTAssertEqual(meta.codexSessionID, "thread-123")
        XCTAssertEqual(meta.codexHome, "/tmp/original-home")
    }

    /// Faz 1.22 + refactor 4.7: uygulama-seviyesi NSEvent monitörü artık TEK
    /// (`TerminalEventMonitor`), manager tarafından kurulur ve kapanışta bırakılır;
    /// çağrı idempotent.
    func testShutdownRemovesEventMonitorIdempotently() {
        let monitor = TerminalEventMonitor()
        let manager = TerminalSessionManager(eventMonitor: monitor)
        XCTAssertTrue(monitor.isRunning, "manager tek monitörü kurmadı")

        manager.shutdown()
        XCTAssertFalse(monitor.isRunning, "shutdown monitörü bırakmadı")
        manager.shutdown()
        XCTAssertFalse(monitor.isRunning)
    }
}
