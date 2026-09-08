import Foundation
import XCTest
import LumiKit
@testable import LumiServices

final class UnityLibraryCopierTests: XCTestCase {
    private var root: URL!
    private let copier = UnityLibraryCopier()

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lumi-library-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testCopiesIndependentlyAndSkipsGeneratedNoise() async throws {
        let source = try makeProject("source")
        let workspace = try makeProject("workspace", library: false)
        try Data("one".utf8).write(to: source.appendingPathComponent("Library/Cache/a"))
        try Data("noise".utf8).write(to: source.appendingPathComponent("Library/Temp/a"))
        try await copier.copy(sourcePath: source.path, workspacePath: workspace.path)
        try Data("two".utf8).write(to: source.appendingPathComponent("Library/Cache/a"))
        XCTAssertEqual(String(data: try Data(contentsOf: workspace.appendingPathComponent("Library/Cache/a")), encoding: .utf8), "one")
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("Library/Temp").path))
    }

    func testRejectsNestedSymlinkWithoutLeavingPartialLibrary() async throws {
        let source = try makeProject("source")
        let workspace = try makeProject("workspace", library: false)
        try Data("secret".utf8).write(to: source.appendingPathComponent("outside"))
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("Library/Bad"), withDestinationURL: source.appendingPathComponent("outside"))
        await XCTAssertThrowsErrorAsync(try await copier.copy(sourcePath: source.path, workspacePath: workspace.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("Library").path))
    }

    func testPreservesPreexistingTarget() async throws {
        let source = try makeProject("source")
        let workspace = try makeProject("workspace", library: false)
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("Library"), withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: workspace.appendingPathComponent("Library/value"))
        await XCTAssertThrowsErrorAsync(try await copier.copy(sourcePath: source.path, workspacePath: workspace.path))
        XCTAssertEqual(String(data: try Data(contentsOf: workspace.appendingPathComponent("Library/value")), encoding: .utf8), "existing")
    }

    func testRejectsSymlinkSourceRoot() async throws {
        let real = try makeProject("real")
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let workspace = try makeProject("workspace", library: false)
        await XCTAssertThrowsErrorAsync(try await copier.copy(sourcePath: link.path, workspacePath: workspace.path))
    }

    func testLockReasonUsesUnityLockfile() throws {
        let source = try makeProject("source")
        let lock = source.appendingPathComponent("Temp/UnityLockfile")
        try Data().write(to: lock)
        XCTAssertNotNil(copier.blockedReason(sourcePath: source.path))
    }

    private func makeProject(_ name: String, library: Bool = true) throws -> URL {
        let project = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: project.appendingPathComponent("Temp"), withIntermediateDirectories: true)
        if library {
            for folder in ["Library/Cache", "Library/Temp", "Library/Logs"] {
                try FileManager.default.createDirectory(at: project.appendingPathComponent(folder), withIntermediateDirectories: true)
            }
        }
        return project
    }
}

private func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T) async {
    do { _ = try await expression(); XCTFail("Expected an error") } catch { }
}
