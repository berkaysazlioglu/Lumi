import Foundation
import LumiKit
@testable import LumiUI
import XCTest

/// Karar 108: All Terminals'tan serbest terminal açma — kapsam intent'i ve
/// dropdown'un konum bölümü.
@MainActor
final class LooseTerminalSpawnTests: XCTestCase {
    private let repoPath = "/tmp/repo"

    func testAllTerminalsSpawnUsesCurrentLooseLocation() async {
        let fixture = await ShellContextFixture.make()

        fixture.context.spawnTerminal(in: .all, command: "claude")

        let calls = fixture.terminalService.spawnCalls
        XCTAssertEqual(calls.map(\.0), [fixture.context.looseTerminals.currentLocation])
        XCTAssertEqual(calls.first?.2.map { $0.hasPrefix("claude") }, true)
    }

    func testRepoSpawnUsesCheckout() async {
        let fixture = await ShellContextFixture.make()

        fixture.context.spawnTerminal(in: .repo(repoPath), command: nil, task: "Bash")

        XCTAssertEqual(fixture.terminalService.spawnCalls.map(\.0), [repoPath])
    }

    func testRepoScopeHasNoLocationSection() async {
        let fixture = await ShellContextFixture.make()

        XCTAssertTrue(NewTerminalMenu.locationItems(shell: fixture.context, scope: .repo(repoPath)).isEmpty)
        XCTAssertNil(NewTerminalMenu.locationLabel(shell: fixture.context, scope: .repo(repoPath)))
    }

    func testAllTerminalsLocationSectionStartsWithCheckedHomeAndEndsWithFolderPicker() async {
        let fixture = await ShellContextFixture.make()

        let items = NewTerminalMenu.locationItems(shell: fixture.context, scope: .all)

        XCTAssertEqual(items.first?.label, "~")
        XCTAssertEqual(items.first?.isSelected, true)
        XCTAssertEqual(items.last?.label, "Choose Folder…")
        XCTAssertEqual(items.filter(\.isSelected).count, 1)
        XCTAssertEqual(NewTerminalMenu.locationLabel(shell: fixture.context, scope: .all), "~")
    }

    func testAllTerminalsMenuItemsSpawnAtLooseLocation() async {
        let fixture = await ShellContextFixture.make()

        NewTerminalMenu.items(shell: fixture.context, scope: .all)
            .first { $0.label == "New Bash" }?
            .action()

        XCTAssertEqual(
            fixture.terminalService.spawnCalls.map(\.0),
            [fixture.context.looseTerminals.currentLocation]
        )
    }
}
