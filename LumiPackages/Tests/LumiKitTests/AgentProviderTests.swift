import LumiKit
import XCTest

/// Provider → UI etiketi / launch komutu eşlemesi (spec/20 §6: "New Claude"
/// butonu spawn sonrası `claude\r` enjekte eder).
final class AgentProviderTests: XCTestCase {
    func testLaunchCommandMatchesCLIExecutableName() {
        XCTAssertEqual(AgentProvider.claude.launchCommand, "claude")
        XCTAssertEqual(AgentProvider.codex.launchCommand, "codex")
    }

    func testDisplayNamesAreCapitalizedForButtons() {
        XCTAssertEqual(AgentProvider.claude.displayName, "Claude")
        XCTAssertEqual(AgentProvider.codex.displayName, "Codex")
    }

    func testAllCasesCoversEveryProvider() {
        // CaseIterable: provider listesi gereken yerler (system checks, settings
        // picker) elle yazılmış dizilere düşmesin
        XCTAssertEqual(Set(AgentProvider.allCases), [.claude, .codex])
    }
}
