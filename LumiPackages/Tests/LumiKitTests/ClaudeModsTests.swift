import LumiKit
import XCTest

/// Karar 142: hangi modun klasörü terminale gider.
final class ClaudeModsTests: XCTestCase {
    private let mods = [
        ClaudeMod(id: "a", name: "A", path: "/m/a"),
        ClaudeMod(id: "b", name: "B", path: "/m/b"),
        ClaudeMod(id: "c", name: "C", path: "/m/c"),
    ]

    func testModWithoutConfigEntryIsEnabled() {
        XCTAssertTrue(ClaudeMods.isEnabled("a", in: .defaults))
    }

    func testEnabledPathsKeepOrderAndDropDisabled() {
        var config = AppConfig.defaults
        config.claudeMods = ["b": false, "c": true]

        XCTAssertEqual(ClaudeMods.enabledPaths(mods, config: config), ["/m/a", "/m/c"])
    }
}
