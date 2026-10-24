import XCTest

/// Decision 132 on demo data: press and hold a project header and drag it onto
/// another card; a tap still folds; `⋯` opens the editor.
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
