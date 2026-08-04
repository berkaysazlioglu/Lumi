import Foundation
import XCTest
import LumiKit
@testable import LumiServices

/// Karar 23: `resumeSessions` ui-state persistence'ı — additive key, tek
/// seferlik tüketimde diskten de SİLİNMELİ (overlay merge eski değeri
/// korumasın diye alan her yazımda overlay'e girer).
final class ResumeSessionPersistenceTests: XCTestCase {
    private var tempHome: URL!
    private var paths: LumiPaths!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-test-\(UUID().uuidString)")
        paths = LumiPaths(mode: .development, homeDirectory: tempHome)
        try paths.ensureDirectoriesExist()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempHome)
        try super.tearDownWithError()
    }

    private func makeService() -> ConfigService {
        ConfigService(paths: paths, writeDebounce: .milliseconds(20))
    }

    private func readJSONDict(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testLegacyUIStateWithoutKeyDecodesToEmptyList() async throws {
        // Arrange — eski sürümün yazdığı ui-state (resumeSessions yok)
        try """
        {"openTabs": ["/repo/a"], "activeTab": null, "leftSidebarOpen": true,
         "rightSidebarOpen": false}
        """.write(to: paths.uiStateFile, atomically: true, encoding: .utf8)
        let service = makeService()

        // Act
        let state = await service.uiState()

        // Assert
        XCTAssertTrue(state.resumeSessions.isEmpty)
    }

    func testResumeSessionsRoundTripThroughDisk() async throws {
        // Arrange
        let service = makeService()
        let entries = [
            ResumeSession(repoPath: "/repo/a", sessionID: "11111111-2222-3333-4444-555555555555"),
            ResumeSession(repoPath: "/repo/b", sessionID: "aaaabbbb-cccc-dddd-eeee-ffff00001111"),
        ]

        // Act
        await service.updateUIState { $0.resumeSessions = entries }
        await service.flushPendingWrites()

        // Assert — taze bir servis diskten aynı listeyi okur
        let reloaded = await makeService().uiState()
        XCTAssertEqual(reloaded.resumeSessions, entries)
    }

    func testConsumingResumeSessionsClearsDiskKey() async throws {
        // Arrange — dolu liste persist edilmiş durumda
        let service = makeService()
        await service.updateUIState {
            $0.resumeSessions = [
                ResumeSession(repoPath: "/repo/a", sessionID: "11111111-2222-3333-4444-555555555555")
            ]
        }
        await service.flushPendingWrites()

        // Act — açılışta tüketim: liste boşaltılır
        await service.updateUIState { $0.resumeSessions = [] }
        await service.flushPendingWrites()

        // Assert — diskte bayat kayıt KALMAZ (overlay merge tuzağı)
        let written = try readJSONDict(paths.uiStateFile)
        let onDisk = written["resumeSessions"] as? [[String: Any]]
        XCTAssertEqual(onDisk?.count, 0)
        let reloaded = await makeService().uiState()
        XCTAssertTrue(reloaded.resumeSessions.isEmpty)
    }
}
