import Foundation
import LumiKit
@testable import LumiUI
import XCTest

/// Karar 54: split-button dropdown'u aktif olmayan ajanları + DeepSeek'i +
/// Bash'i taşır; aktif sağlayıcı ana butonda olduğu için listede yer almaz.
@MainActor
final class NewTerminalMenuTests: XCTestCase {
    private let repoPath = "/tmp/repo"

    private let modelLabels = ["New Claude Fable", "New Claude Opus", "New Claude Sonnet", "New Claude Haiku"]

    func testListsModelsThenTheOtherProviderThenDeepSeekThenBash() async {
        let fixture = await ShellContextFixture.make()

        let labels = NewTerminalMenu.items(shell: fixture.context, scope: .repo(repoPath)).map(\.label)

        XCTAssertEqual(labels, modelLabels + ["New Codex", "New DeepSeek", "New Bash"])
    }

    func testActiveProviderIsExcluded() async {
        let fixture = await ShellContextFixture.make()
        fixture.context.settings.setProvider(.codex)

        let labels = NewTerminalMenu.items(shell: fixture.context, scope: .repo(repoPath)).map(\.label)

        XCTAssertEqual(labels, modelLabels + ["New Claude", "New DeepSeek", "New Bash"])
    }

    /// Karar 121: ayar kapalıyken model kısayolları listelenmez.
    func testModelShortcutsAreHiddenWhenDisabled() async {
        let fixture = await ShellContextFixture.make()
        fixture.context.settings.setClaudeModelShortcutsEnabled(false)

        let labels = NewTerminalMenu.items(shell: fixture.context, scope: .repo(repoPath)).map(\.label)

        XCTAssertEqual(labels, ["New Codex", "New DeepSeek", "New Bash"])
    }

    func testModelItemSpawnsClaudeWithTheAlias() async {
        let fixture = await ShellContextFixture.make()

        let item = try? XCTUnwrap(
            NewTerminalMenu.items(shell: fixture.context, scope: .repo(repoPath))
                .first { $0.label == "New Claude Fable" }
        )
        item?.action()

        let spawned = fixture.terminalService.spawnCalls
        XCTAssertEqual(spawned.count, 1)
        XCTAssertEqual(spawned.first?.task, "Fable")
        XCTAssertEqual(spawned.first?.command, "claude --model fable")
    }

    func testDeepSeekItemRefusesToSpawnWhenNotConfigured() async {
        let fixture = await ShellContextFixture.make()
        await fixture.context.deepSeek.load()

        let item = try? XCTUnwrap(
            NewTerminalMenu.items(shell: fixture.context, scope: .repo(repoPath))
                .first { $0.label == "New DeepSeek" }
        )
        item?.action()

        XCTAssertTrue(fixture.context.terminals.terminals.isEmpty)
        XCTAssertEqual(fixture.context.toasts.toasts.map(\.kind), [.info])
    }

    func testDeepSeekItemSourcesTheEnvFileWhenConfigured() async {
        let fixture = await ShellContextFixture.make()
        fixture.context.deepSeek.apiKeyDraft = "sk-ready"
        await fixture.context.deepSeek.install()

        let item = try? XCTUnwrap(
            NewTerminalMenu.items(shell: fixture.context, scope: .repo(repoPath))
                .first { $0.label == "New DeepSeek" }
        )
        item?.action()

        let spawned = fixture.terminalService.spawnCalls
        XCTAssertEqual(spawned.count, 1)
        XCTAssertEqual(spawned.first?.task, "DeepSeek")
        XCTAssertEqual(spawned.first?.command, "source \"/tmp/lumi-tests/.claude/deepseek.env\" && claude")
    }

    func testBashItemSpawnsAPlainShell() async {
        let fixture = await ShellContextFixture.make()

        let item = try? XCTUnwrap(
            NewTerminalMenu.items(shell: fixture.context, scope: .repo(repoPath))
                .first { $0.label == "New Bash" }
        )
        item?.action()

        let spawned = fixture.terminalService.spawnCalls
        XCTAssertEqual(spawned.count, 1)
        XCTAssertEqual(spawned.first?.task, "Bash")
        XCTAssertNil(spawned.first?.command)
    }
}
