import Foundation
import LumiKit
import LumiState
import LumiTestSupport
import XCTest
@testable import LumiAppCore

/// Karar 142: açık modların klasörleri terminal servisine — açılışta, ayar
/// değişince ve klasör yeniden taranınca.
@MainActor
final class ClaudeModsAssemblyTests: XCTestCase {
    private var registry: FakeServiceRegistry!
    private var modService: FakeClaudeModService!
    private var assembly: ClaudeModsAssembly!

    override func setUp() async throws {
        registry = FakeServiceRegistry()
        modService = FakeClaudeModService(mods: [
            ClaudeMod(id: "image-preview", name: "image-preview", path: "/m/image-preview", isBundled: true),
            ClaudeMod(id: "mine", name: "mine", path: "/m/mine"),
        ])
        registry.claudeMods = modService
        let shared = SharedStores.make(config: registry.config, terminal: registry.terminal, toastAutoDismissAfter: 60)
        assembly = ClaudeModsAssembly()
        assembly.build(services: registry, shared: shared)
    }

    override func tearDown() async throws {
        await assembly.shutdown()
        registry.removeTemporaryDirectories()
    }

    func testStartInstallsBundledModsAndPublishesEnabledFolders() async {
        var config = AppConfig.defaults
        config.claudeMods = ["mine": false]
        await registry.fakeConfig.seed(config)

        await assembly.start()

        let installs = await modService.installCount
        XCTAssertEqual(installs, 1)
        XCTAssertEqual(registry.fakeTerminal.claudePluginDirectories.last, ["/m/image-preview"])
    }

    func testToggleRepublishesOnlyWhenModMapChanges() async {
        await assembly.start()
        let afterStart = registry.fakeTerminal.claudePluginDirectories.count

        var unrelated = AppConfig.defaults
        unrelated.claudeModelShortcutsEnabled = false
        assembly.configDidChange(old: .defaults, new: unrelated)
        XCTAssertEqual(registry.fakeTerminal.claudePluginDirectories.count, afterStart)

        var disabled = unrelated
        disabled.claudeMods = ["image-preview": false]
        assembly.configDidChange(old: unrelated, new: disabled)
        XCTAssertEqual(registry.fakeTerminal.claudePluginDirectories.last, ["/m/mine"])
    }

    func testRescanPublishesNewlyAddedMod() async {
        await assembly.start()
        await modService.setMods([ClaudeMod(id: "new", name: "new", path: "/m/new")])

        await assembly.store.reload()

        XCTAssertEqual(registry.fakeTerminal.claudePluginDirectories.last, ["/m/new"])
    }
}
