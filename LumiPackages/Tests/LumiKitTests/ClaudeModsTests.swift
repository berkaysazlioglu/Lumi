import LumiKit
import XCTest

/// Karar 142: hangi modun klasörü terminale gider.
final class ClaudeModsTests: XCTestCase {
    private let lumi = ClaudeMod(id: "lumi", name: "lumi", path: "/m/lumi", isBundled: true)
    private let mine = ClaudeMod(id: "mine", name: "mine", path: "/m/mine")
    private let other = ClaudeMod(id: "other", name: "other", path: "/m/other")

    func testWithoutConfigEntryLumiModIsOnAndUserModIsOff() {
        XCTAssertTrue(ClaudeMods.isEnabled(lumi, in: .defaults))
        XCTAssertFalse(ClaudeMods.isEnabled(mine, in: .defaults))
    }

    func testEnabledPathsFollowConfigAndKeepOrder() {
        var config = AppConfig.defaults
        config.claudeMods = ["lumi": false, "mine": true]

        XCTAssertEqual(ClaudeMods.enabledPaths([lumi, mine, other], config: config), ["/m/mine"])
    }
}
