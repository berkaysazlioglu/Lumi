import XCTest

/// Decision 132 on demo data: press and hold a project header and drag it onto
/// another card; a tap still folds; `⋯` opens the editor; `+` opens the
/// agent menu (decision 133).
@MainActor
final class ProjectReorderUITests: XCTestCase {
    func testDragProjectHeaderOntoAnother() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-demoMode", "YES"]
        app.launch()

        let first = header(app, "word-puzzle")
        let second = header(app, "liman")
        guard first.waitForExistence(timeout: 10), second.exists else {
            throw XCTSkip("demo projects not shown")
        }
        XCTAssertLessThan(first.frame.minY, second.frame.minY)

        // Slow, with a hold over the target — a flick ends the drag before the
        // drop target registers.
        first.press(forDuration: 1.2, thenDragTo: second, withVelocity: .slow, thenHoldForDuration: 0.8)

        let deadline = Date().addingTimeInterval(5)
        while first.frame.minY < second.frame.minY && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertGreaterThan(first.frame.minY, second.frame.minY, "dropped project should take the target's place")
        // The lifting finger must not fold the dropped card.
        let agent = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Fix tile drop animation")).firstMatch
        XCTAssertTrue(agent.exists, "dropped project should stay expanded")
    }

    /// Decision 133: the checkout `+` opens a menu instead of starting at once.
    func testPlusOpensAgentMenu() throws {
        let app = XCUIApplication()
        // The argument domain pins the setting off whatever an earlier run saved.
        app.launchArguments += ["-demoMode", "YES", "-showsClaudeModelShortcuts", "NO"]
        app.launch()

        let plus = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "New agent on")).firstMatch
        guard plus.waitForExistence(timeout: 10) else { throw XCTSkip("demo projects not shown") }
        plus.tap()
        XCTAssertTrue(app.buttons["Claude"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Codex"].isEnabled)
        XCTAssertFalse(app.buttons["Bash"].isEnabled)
        // Model shortcuts are off by default (Settings ▸ Claude Models).
        XCTAssertFalse(app.buttons["Claude Opus"].exists)
    }

    func testClaudeModelsSettingShowsShortcutsInPlusMenu() throws {
        let app = XCUIApplication()
        // No argument for the setting itself: it would shadow the toggle's write.
        app.launchArguments += ["-demoMode", "YES"]
        app.launch()

        app.buttons["Settings"].tap()
        let toggle = app.switches.matching(NSPredicate(format: "label CONTAINS %@", "Claude Models")).firstMatch
        guard toggle.waitForExistence(timeout: 5) else { return XCTFail("settings screen should open") }
        if toggle.value as? String != "1" {
            // The switch sits at the cell's trailing edge; the label alone doesn't flip it.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, "1")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForNonExistence(timeout: 3))

        let plus = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "New agent on")).firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        plus.tap()
        XCTAssertTrue(app.buttons["Claude Opus"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Claude Opus"].isEnabled)
    }

    func testHeaderTapStillFoldsAndMenuOpensEditor() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-demoMode", "YES"]
        app.launch()

        let header = header(app, "word-puzzle")
        guard header.waitForExistence(timeout: 10) else { throw XCTSkip("demo projects not shown") }
        // A quick tap still folds the card — the reorder only takes a press and hold.
        let agent = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Fix tile drop animation")).firstMatch
        XCTAssertTrue(agent.exists)
        header.tap()
        XCTAssertTrue(agent.waitForNonExistence(timeout: 3))
        header.tap()
        XCTAssertTrue(agent.waitForExistence(timeout: 3))

        app.buttons["Project Actions"].firstMatch.tap()
        let edit = app.buttons["Edit Project…"]
        XCTAssertTrue(edit.waitForExistence(timeout: 3))
        edit.tap()
        XCTAssertTrue(app.navigationBars["Edit Project"].waitForExistence(timeout: 3))
    }

    /// A project header: its label carries the badge emoji before the name.
    private func header(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }
}
