import LumiKit
import XCTest

/// Provider → launch komutu eşlemesi ("New Claude" butonu spawn sonrası
/// `claude\r` enjekte eder). UI etiketi artık LumiUI presenter'ında
/// (refactor 5.9) — `AgentProviderPresentationTests`.
final class AgentProviderTests: XCTestCase {
    func testLaunchCommandMatchesCLIExecutableName() {
        XCTAssertEqual(AgentProvider.claude.launchCommand, "claude")
        XCTAssertEqual(AgentProvider.codex.launchCommand, "codex")
    }

    func testAllCasesCoversEveryProvider() {
        // CaseIterable: provider listesi gereken yerler (system checks, settings
        // picker) elle yazılmış dizilere düşmesin
        XCTAssertEqual(Set(AgentProvider.allCases), [.claude, .codex])
    }
}
