import LumiKit
import XCTest

/// Karar 119: legacy projeler kökünün `additionalPaths`'e tek seferlik taşınması.
final class LegacyProjectsRootMigrationTests: XCTestCase {
    private func config(root: String, paths: [AdditionalPath] = []) -> AppConfig {
        var config = AppConfig.defaults
        config.projectsRoot = root
        config.additionalPaths = paths
        return config
    }

    func testMovesRootToFrontOfAdditionalPathsAndClearsIt() {
        let existing = AdditionalPath(id: "a", path: "/other", type: .repo)
        var subject = config(root: "/Users/me/code", paths: [existing])

        LegacyProjectsRootMigration.migrate(&subject)

        XCTAssertEqual(subject.projectsRoot, "")
        XCTAssertEqual(subject.additionalPaths.map(\.path), ["/Users/me/code", "/other"])
        XCTAssertEqual(subject.additionalPaths.first?.type, .root)
        XCTAssertTrue(subject.onboardingCompleted)
    }

    func testSecondRunIsNoOp() {
        var subject = config(root: "/Users/me/code")
        LegacyProjectsRootMigration.migrate(&subject)
        let afterFirst = subject

        LegacyProjectsRootMigration.migrate(&subject)

        XCTAssertEqual(subject, afterFirst, "boşalan kök tekrar eklenmez")
    }

    func testAlreadyListedRepoIsUpgradedToRoot() {
        let existing = AdditionalPath(id: "a", path: "~/code", type: .repo)
        var subject = config(root: NSHomeDirectory() + "/code", paths: [existing])

        LegacyProjectsRootMigration.migrate(&subject)

        XCTAssertEqual(subject.additionalPaths.count, 1)
        XCTAssertEqual(subject.additionalPaths.first?.id, "a")
        XCTAssertEqual(subject.additionalPaths.first?.type, .root, "alt klasör taraması kaybolmaz")
    }

    func testAlreadyListedRootIsOnlyCleared() {
        let existing = AdditionalPath(id: "a", path: "/Users/me/code/", type: .root)
        var subject = config(root: "/Users/me/code", paths: [existing])

        LegacyProjectsRootMigration.migrate(&subject)

        XCTAssertEqual(subject.additionalPaths, [existing])
        XCTAssertEqual(subject.projectsRoot, "")
    }

    func testEmptyRootLeavesConfigUntouched() {
        var subject = config(root: "  ")
        let before = subject

        LegacyProjectsRootMigration.migrate(&subject)

        XCTAssertEqual(subject, before)
        XCTAssertFalse(subject.onboardingCompleted)
    }

    func testAddingSkipsTildeEquivalentPath() {
        let home = NSHomeDirectory()
        let existing = AdditionalPath(id: "a", path: "~/code", type: .root)

        let result = AdditionalPath.adding(home + "/code", type: .root, to: [existing])

        XCTAssertEqual(result, [existing])
    }
}
