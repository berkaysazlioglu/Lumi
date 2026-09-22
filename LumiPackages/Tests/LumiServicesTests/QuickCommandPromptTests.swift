import XCTest
import LumiKit
@testable import LumiServices

final class QuickCommandPromptTests: XCTestCase {
    func testSystemPromptListsEveryPlaceholderAndForbidsHardcodedRoot() {
        let prompt = QuickCommandPrompt.systemPrompt(projectPath: "/projects/game")
        for placeholder in QuickCommandPlaceholder.allCases {
            XCTAssertTrue(prompt.contains(placeholder.token), "\(placeholder.token) missing")
        }
        XCTAssertTrue(prompt.contains("Never hard-code /projects/game"))
        XCTAssertTrue(prompt.contains("```sh"))
    }

    func testBodyIncludesCurrentScriptOnlyWhenPresent() {
        let fresh = QuickCommandPrompt.body(for: .init(projectPath: "/p", projectName: "P", description: " run tests \n"))
        XCTAssertTrue(fresh.contains("Command I want:\nrun tests\n"))
        XCTAssertFalse(fresh.contains("Current script"))

        let refine = QuickCommandPrompt.body(for: .init(projectPath: "/p", projectName: "P", description: "x", currentScript: "make\n"))
        XCTAssertTrue(refine.contains("Current script (improve or replace it):\n```sh\nmake\n```"))
    }

    func testExtractScriptPrefersFirstShellFence() {
        let reply = "Intro text.\n```bash\necho one\n```\n```sh\necho two\n```"
        XCTAssertEqual(QuickCommandPrompt.extractScript(from: reply), "echo one\n")
        XCTAssertEqual(QuickCommandPrompt.extractScript(from: "```\nls\n"), "ls\n", "unterminated fence keeps the rest")
        XCTAssertEqual(QuickCommandPrompt.extractScript(from: "ls -la"), "ls -la\n", "no fence → whole reply")
        XCTAssertNil(QuickCommandPrompt.extractScript(from: "  \n"))
    }

    func testNonShellFenceIsNotMistakenForTheScript() {
        let reply = "```json\n{}\n```\n```sh\nmake\n```"
        XCTAssertEqual(QuickCommandPrompt.extractScript(from: reply), "make\n")
    }
}
