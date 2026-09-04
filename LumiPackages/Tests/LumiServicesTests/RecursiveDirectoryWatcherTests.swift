import XCTest
@testable import LumiServices

/// FSEvents path filtresi (karar 28): exclude'lu dizinlerdeki yazmalar tam
/// rescan tetiklemez; `.git` içi değişimler tetikler (git panel canlılığı).
final class RecursiveDirectoryWatcherTests: XCTestCase {
    private let root = "/Users/x/proj"
    private let excluded: Set<String> = ["node_modules", "Library", "Temp"]

    private func isRelevant(_ path: String) -> Bool {
        RecursiveDirectoryWatcher.isRelevantEvent(path: path, root: root, excludedNames: excluded)
    }

    func testEventInsideExcludedDirectoryIsNoise() {
        XCTAssertFalse(isRelevant("/Users/x/proj/Library/ArtifactDB/data"))
        XCTAssertFalse(isRelevant("/Users/x/proj/src/node_modules/pkg"))
        XCTAssertFalse(isRelevant("/Users/x/proj/Temp"))
    }

    func testEventOnSourceOrGitIsRelevant() {
        XCTAssertTrue(isRelevant("/Users/x/proj/src/main.swift"))
        XCTAssertTrue(isRelevant("/Users/x/proj/.git/index"))
        XCTAssertTrue(isRelevant("/Users/x/proj"), "kökün kendisi (rescan bayrağı) daima ilgili")
    }

    func testExcludedNameOutsideRootDoesNotMatch() {
        // Kök path'inin kendi bileşenleri filtrelenmez
        XCTAssertTrue(
            RecursiveDirectoryWatcher.isRelevantEvent(
                path: "/Users/x/Library/proj/file",
                root: "/Users/x/Library/proj",
                excludedNames: excluded
            )
        )
    }

    func testAnyRelevantPathInBatchTriggers() {
        let paths = ["/Users/x/proj/Library/a", "/Users/x/proj/README.md"]
        XCTAssertTrue(
            RecursiveDirectoryWatcher.containsRelevantEvent(paths: paths, root: root, excludedNames: excluded)
        )
        XCTAssertFalse(
            RecursiveDirectoryWatcher.containsRelevantEvent(
                paths: ["/Users/x/proj/Library/a"], root: root, excludedNames: excluded
            )
        )
    }
}
