import XCTest
@testable import LumiState

final class ProjectToolsTabTests: XCTestCase {
    func testAvailableTabsForGitRepo() {
        XCTAssertEqual(ProjectToolsTab.available(isGitRepo: true), [.explorer, .agentHistory, .sourceControl])
    }

    func testAvailableTabsForFolderWorkspace() {
        XCTAssertEqual(ProjectToolsTab.available(isGitRepo: false), [.explorer, .agentHistory])
    }
}
