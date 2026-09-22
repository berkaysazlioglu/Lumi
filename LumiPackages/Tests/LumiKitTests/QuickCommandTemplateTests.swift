import XCTest
@testable import LumiKit

final class QuickCommandTemplateTests: XCTestCase {
    private let context = QuickCommandContext(
        path: "/work/game review", projectPath: "/projects/game", name: "review", branch: "feature/review"
    )

    func testResolvesEveryKnownPlaceholder() {
        let script = #"cd "{path}" && cp -R "{project_path}/Library" . && echo {name} {branch}"#
        XCTAssertEqual(
            QuickCommandTemplate.resolve(script, context: context),
            #"cd "/work/game review" && cp -R "/projects/game/Library" . && echo review feature/review"#
        )
    }

    func testShellVariablesAndUnknownKeysAreUntouched() {
        let script = #"echo ${path} ${HOME} {unknown} {path}"#
        XCTAssertEqual(QuickCommandTemplate.resolve(script, context: context), #"echo ${path} ${HOME} {unknown} /work/game review"#)
    }

    func testMultilineAndNonASCIIScriptsSurvive() {
        let script = "# Türkçe açıklama ✨\nls {path}\n"
        XCTAssertEqual(QuickCommandTemplate.resolve(script, context: context), "# Türkçe açıklama ✨\nls /work/game review\n")
    }

    func testValidityRequiresNameAndScript() {
        XCTAssertFalse(ProjectQuickCommand(projectPath: "/p", name: " ", script: "ls").isValid)
        XCTAssertFalse(ProjectQuickCommand(projectPath: "/p", name: "List", script: "\n").isValid)
        XCTAssertTrue(ProjectQuickCommand(projectPath: "/p", name: "List", script: "ls").isValid)
    }
}

final class QuickCommandNamingTests: XCTestCase {
    func testSuggestedNameUsesFirstLineWithoutTrailingPunctuation() {
        XCTAssertEqual(QuickCommandNaming.suggestedName(from: "\n  Open Unity here.\nmore"), "Open Unity here")
        XCTAssertEqual(QuickCommandNaming.suggestedName(from: ""), "")
    }

    func testLongNameIsCutAtWordBoundary() {
        let name = QuickCommandNaming.suggestedName(from: "Build the release app bundle and install it into the Applications folder")
        XCTAssertEqual(name, "Build the release app bundle and install…")
        XCTAssertLessThanOrEqual(name.count, QuickCommandNaming.maxNameLength + 1)
    }
}

final class QuickCommandRunTests: XCTestCase {
    func testFileNameIsStablePerCommandAndCheckout() {
        XCTAssertEqual(QuickCommandRun.fileName(commandID: "A-1", checkoutName: "Sand Blocks"), "A-1-Sand-Blocks.sh")
        XCTAssertEqual(QuickCommandRun.fileName(commandID: "A-1", checkoutName: "../"), "A-1-checkout.sh", "no traversal, no empty slug")
    }

    func testLaunchLineQuotesThePath() {
        XCTAssertEqual(QuickCommandRun.launchLine(scriptPath: "/a b/it's.sh"), #"sh '/a b/it'\''s.sh'"#)
    }

    func testScriptContentsAddHeaderAndTrailingNewline() {
        let command = ProjectQuickCommand(projectPath: "/p", name: "Two\nlines", script: "ls {path}")
        let context = QuickCommandContext(path: "/w", projectPath: "/p", name: "w", branch: "")
        XCTAssertEqual(QuickCommandRun.scriptContents(command, context: context), "# Lumi action: Two lines\nls /w\n")
    }

    func testShebangStaysOnTheFirstLine() {
        let command = ProjectQuickCommand(projectPath: "/p", name: "Start App", script: "#!/bin/sh\nopen \"{path}\"")
        let context = QuickCommandContext(path: "/w", projectPath: "/p", name: "w", branch: "")
        XCTAssertEqual(
            QuickCommandRun.scriptContents(command, context: context),
            "#!/bin/sh\n# Lumi action: Start App\nopen \"/w\"\n"
        )
    }
}
