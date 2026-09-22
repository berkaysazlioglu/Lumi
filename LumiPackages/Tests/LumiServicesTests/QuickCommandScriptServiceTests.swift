import XCTest
import LumiKit
@testable import LumiServices

final class QuickCommandScriptServiceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumi-qc-\(UUID().uuidString)")
            .appendingPathComponent("quick-commands")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    func testWritesPrivateFileAndOverwritesOnRerun() async throws {
        let service = QuickCommandScriptService(directory: directory)
        let path = try await service.writeScript(named: "a-main.sh", contents: "echo 1\n")
        _ = try await service.writeScript(named: "a-main.sh", contents: "echo 2\n")
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "echo 2\n")
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testRejectsNamesOutsideTheDirectory() async {
        let service = QuickCommandScriptService(directory: directory)
        do {
            _ = try await service.writeScript(named: "../escape.sh", contents: "x")
            XCTFail("hata bekleniyordu")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.deletingLastPathComponent().appendingPathComponent("escape.sh").path))
    }
}
