import Foundation
import LumiKit
import XCTest

@testable import LumiServices

/// Refactor 3.9 (design/02 §8 sapmasının kapatılması): trash/reveal artık
/// bilinen kökler dışında çalışmaz.
final class FileSystemOperationsTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []

        func record(_ url: URL) {
            lock.lock()
            urls.append(url)
            lock.unlock()
        }

        var captured: [URL] {
            lock.lock()
            defer { lock.unlock() }
            return urls
        }
    }

    private func makeOperations(
        roots: [String],
        trashed: Recorder = Recorder(),
        revealed: Recorder = Recorder()
    ) -> FileSystemOperations {
        FileSystemOperations(
            allowedRoots: { roots },
            trashItem: { trashed.record($0) },
            reveal: { revealed.record($0) }
        )
    }

    func testTrashAllowsPathInsideKnownRoot() async throws {
        let trashed = Recorder()
        let operations = makeOperations(roots: ["/tmp/lumi-roots"], trashed: trashed)

        try await operations.trash(path: "/tmp/lumi-roots/proj/a.txt")

        XCTAssertEqual(trashed.captured.map(\.path), ["/tmp/lumi-roots/proj/a.txt"])
    }

    func testTrashRejectsPathOutsideKnownRoots() async {
        let trashed = Recorder()
        let operations = makeOperations(roots: ["/tmp/lumi-roots"], trashed: trashed)

        do {
            try await operations.trash(path: "/etc/passwd")
            XCTFail("kök dışı path reddedilmeliydi")
        } catch let error as LumiError {
            XCTAssertEqual(error, .pathOutsideRepo(path: "/etc/passwd"))
        } catch {
            XCTFail("beklenmeyen hata: \(error)")
        }
        XCTAssertTrue(trashed.captured.isEmpty, "reddedilen path çöpe gitmemeli")
    }

    func testTrashRejectsTraversalEscapingTheRoot() async {
        let operations = makeOperations(roots: ["/tmp/lumi-roots"])

        do {
            try await operations.trash(path: "/tmp/lumi-roots/../../etc/passwd")
            XCTFail("traversal reddedilmeliydi")
        } catch let error as LumiError {
            guard case .pathOutsideRepo = error else {
                return XCTFail("pathOutsideRepo bekleniyordu, gelen: \(error)")
            }
        } catch {
            XCTFail("beklenmeyen hata: \(error)")
        }
    }

    func testTrashFailureIsMappedToFileOperationFailed() async {
        struct Boom: Error {}
        let operations = FileSystemOperations(
            allowedRoots: { ["/tmp/lumi-roots"] },
            trashItem: { _ in throw Boom() },
            reveal: { _ in }
        )

        do {
            try await operations.trash(path: "/tmp/lumi-roots/a.txt")
            XCTFail("hata bekleniyordu")
        } catch let error as LumiError {
            guard case .fileOperationFailed(let path, _) = error else {
                return XCTFail("fileOperationFailed bekleniyordu, gelen: \(error)")
            }
            XCTAssertEqual(path, "/tmp/lumi-roots/a.txt")
        } catch {
            XCTFail("beklenmeyen hata: \(error)")
        }
    }

    func testRevealIsSilentNoOpOutsideKnownRoots() async {
        let revealed = Recorder()
        let operations = makeOperations(roots: ["/tmp/lumi-roots"], revealed: revealed)

        await operations.revealInFinder(path: "/etc")
        XCTAssertTrue(revealed.captured.isEmpty)

        await operations.revealInFinder(path: "/tmp/lumi-roots/a.txt")
        XCTAssertEqual(revealed.captured.count, 1)
    }

    func testEmptyRootListFallsBackToHomeDirectory() async throws {
        let trashed = Recorder()
        let operations = makeOperations(roots: [], trashed: trashed)
        let insideHome = (NSHomeDirectory() as NSString).appendingPathComponent("lumi-test.txt")

        try await operations.trash(path: insideHome)

        XCTAssertEqual(trashed.captured.count, 1)
    }
}
