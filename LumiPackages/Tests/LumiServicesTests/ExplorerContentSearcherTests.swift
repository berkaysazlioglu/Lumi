import XCTest
@testable import LumiServices

final class ExplorerContentSearcherTests: XCTestCase {
    func testUtf8CaseInsensitiveHitsAndBinarySkipped() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        try put("first\nNeedle here\nlast", root.appendingPathComponent("a.txt"))
        try Data([0, 1, 2, 78]).write(to: root.appendingPathComponent("b.bin"))
        let result = try await ExplorerContentSearcher.search(repoPath: root.path, paths: ["a.txt", "b.bin"], query: "NEEDLE")
        XCTAssertEqual(result.matches.map(\.line), [2])
        XCTAssertEqual(result.matches.first?.path, "a.txt")
    }

    func testOutsidePathIsIgnoredAndLargeFileSetsLimit() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try put("secret", outside)
        try Data(repeating: 65, count: 2 * 1024 * 1024 + 1).write(to: root.appendingPathComponent("large.txt"))
        let result = try await ExplorerContentSearcher.search(repoPath: root.path, paths: ["../" + outside.lastPathComponent, "large.txt"], query: "secret")
        XCTAssertTrue(result.matches.isEmpty)
        XCTAssertTrue(result.isLimited)
        try? FileManager.default.removeItem(at: outside)
    }

    func testCapsAtFiveHundredResults() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        try put(String(repeating: "hit\n", count: 600), root.appendingPathComponent("many.txt"))
        let result = try await ExplorerContentSearcher.search(repoPath: root.path, paths: ["many.txt"], query: "hit")
        XCTAssertEqual(result.matches.count, 500)
        XCTAssertTrue(result.isLimited)
    }

    private func makeRoot() throws -> URL { let u = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u }
    private func put(_ value: String, _ url: URL) throws { try Data(value.utf8).write(to: url) }
}
