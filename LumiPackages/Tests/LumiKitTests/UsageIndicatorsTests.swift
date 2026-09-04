import XCTest

@testable import LumiKit

final class UsageIndicatorsTests: XCTestCase {
    func testDefaultKeepsClaudeOnAndCodexOff() {
        // Mevcut davranışın korunması: bugün topbar'da yalnız Claude var.
        XCTAssertTrue(UsageIndicators.defaults.claude)
        XCTAssertFalse(UsageIndicators.defaults.codex)
        XCTAssertEqual(UsageIndicators.defaults.enabledProviders, [.claude])
    }

    func testSettingReturnsNewValueWithoutMutatingOriginal() {
        let original = UsageIndicators.defaults

        let updated = original.setting(true, for: .codex)

        XCTAssertFalse(original.codex, "kaynak değer değişmemeli")
        XCTAssertTrue(updated.codex)
        XCTAssertTrue(updated.claude, "diğer sağlayıcı etkilenmemeli")
    }

    func testEnabledProvidersFollowsAgentProviderOrder() {
        let both = UsageIndicators(claude: true, codex: true)

        XCTAssertEqual(both.enabledProviders, AgentProvider.allCases)
    }

    func testNoneEnabledYieldsEmptyList() {
        XCTAssertTrue(UsageIndicators(claude: false, codex: false).enabledProviders.isEmpty)
    }
}
