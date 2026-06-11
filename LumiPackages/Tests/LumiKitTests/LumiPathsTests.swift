import Foundation
import XCTest
@testable import LumiKit

final class LumiPathsTests: XCTestCase {
    private var tempHome: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-paths-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempHome)
        try super.tearDownWithError()
    }

    func testDevelopmentUsesLumiDevDirectory() {
        let paths = LumiPaths(mode: .development, homeDirectory: tempHome)
        XCTAssertEqual(paths.configDir.lastPathComponent, ".lumi-dev")
        XCTAssertTrue(paths.tempDir.path.hasSuffix("lumi-dev"))
    }

    func testProductionPrefersExistingLumiDirectory() throws {
        try FileManager.default.createDirectory(
            at: tempHome.appendingPathComponent(".lumi"),
            withIntermediateDirectories: true
        )
        let paths = LumiPaths(mode: .production, homeDirectory: tempHome)
        XCTAssertEqual(paths.configDir.lastPathComponent, ".lumi")
    }

    func testProductionFallsBackToLegacyPulpo() throws {
        // ~/.lumi yok ama legacy ~/.pulpo var → yerinde kullanılır (migration değil)
        try FileManager.default.createDirectory(
            at: tempHome.appendingPathComponent(".pulpo"),
            withIntermediateDirectories: true
        )
        let paths = LumiPaths(mode: .production, homeDirectory: tempHome)
        XCTAssertEqual(paths.configDir.lastPathComponent, ".pulpo")
    }

    func testProductionFallsBackToAiOrchestratorAfterPulpo() throws {
        try FileManager.default.createDirectory(
            at: tempHome.appendingPathComponent(".ai-orchestrator"),
            withIntermediateDirectories: true
        )
        let paths = LumiPaths(mode: .production, homeDirectory: tempHome)
        XCTAssertEqual(paths.configDir.lastPathComponent, ".ai-orchestrator")
    }

    func testProductionFreshInstallUsesLumi() {
        let paths = LumiPaths(mode: .production, homeDirectory: tempHome)
        XCTAssertEqual(paths.configDir.lastPathComponent, ".lumi")
    }

    func testEnsureDirectoriesCreatesConfigAndTemp() throws {
        let paths = LumiPaths(mode: .development, homeDirectory: tempHome)
        try paths.ensureDirectoriesExist()
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.configDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.tempDir.path))
    }
}
