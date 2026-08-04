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
}
