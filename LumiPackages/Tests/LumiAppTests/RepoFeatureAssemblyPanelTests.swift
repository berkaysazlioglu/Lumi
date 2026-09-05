import XCTest
import LumiUI
@testable import LumiAppCore

@MainActor
final class RepoFeatureAssemblyPanelTests: XCTestCase {
    func testRegistersOnlyProjectToolsPanel() {
        let registries = ShellRegistries()
        RepoFeatureAssembly().registerShellItems(into: registries)
        XCTAssertEqual(registries.panels.all.map(\.id), [.projectTools])
    }
}
