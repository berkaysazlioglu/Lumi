import XCTest
import LumiKit
@testable import LumiServices

final class ExplorerFileEditorTests: XCTestCase {
    func testCreateMoveAndGuards() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let outside = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let editor = ExplorerFileEditor()
        try editor.apply(.createFile(path: "a.txt"), repoPath: root.path)
        XCTAssertThrowsError(try editor.apply(.createFile(path: "a.txt"), repoPath: root.path))
        try editor.apply(.move(from: "a.txt", to: "b.txt"), repoPath: root.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("b.txt").path))
        XCTAssertThrowsError(try editor.apply(.createFile(path: "../escape"), repoPath: root.path))
        XCTAssertThrowsError(try editor.apply(.createFile(path: ".git/config"), repoPath: root.path))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("out").path, withDestinationPath: outside.path)
        XCTAssertThrowsError(try editor.apply(.createFile(path: "out/x"), repoPath: root.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("x").path))
        try editor.apply(.createFolder(path: "folder"), repoPath: root.path)
        XCTAssertThrowsError(try editor.apply(.createFolder(path: "folder"), repoPath: root.path))
    }
}
