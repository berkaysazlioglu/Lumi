import Foundation
import LumiKit
import LumiState
import XCTest
@testable import LumiUI

/// Karar 57: store'un ürettiği niyet kabukta gerçek etkiye dönüşür.
@MainActor
final class TerminalLinkShellIntentTests: XCTestCase {
    private var fixture: ShellContextFixture!

    override func setUp() async throws {
        fixture = await ShellContextFixture.make()
    }

    override func tearDown() async throws {
        fixture.stop()
        fixture = nil
    }

    private var context: ShellContext { fixture.context }

    func testSwitchWorkspaceOpensTheTab() {
        context.performTerminalLinkIntent(.switchWorkspace(path: "/r/beta"))

        XCTAssertEqual(context.navigation.activeRepoPath, "/r/beta")
    }

    func testRevealInFinderGoesThroughShellActions() {
        context.performTerminalLinkIntent(.revealInFinder(path: "/r/alpha/src"))

        XCTAssertEqual(fixture.recorder.revealedPaths, ["/r/alpha/src"])
    }

    func testOpenWithDefaultAppGoesThroughShellActions() {
        context.performTerminalLinkIntent(.openWithDefaultApp(path: "/tmp/report.pdf"))

        XCTAssertEqual(fixture.recorder.openedPaths, ["/tmp/report.pdf"])
    }

    /// Karar 116: `.html` dosyası varsayılan uygulamaya değil tarayıcıya gider.
    func testOpenInBrowserGoesThroughShellActions() {
        context.performTerminalLinkIntent(.openInBrowser(path: "/tmp/index.html"))

        XCTAssertEqual(fixture.recorder.browserOpenedPaths, ["/tmp/index.html"])
        XCTAssertTrue(fixture.recorder.openedPaths.isEmpty)
    }

    /// Lumi içine tarayıcı konmadı: URL sistemin varsayılan tarayıcısına gider.
    func testOpenURLGoesToTheSystemBrowser() {
        let url = URL(string: "https://lumi.dev")!

        context.performTerminalLinkIntent(.openURL(url))

        XCTAssertEqual(fixture.recorder.openedURLs, [url])
        XCTAssertTrue(fixture.recorder.openedPaths.isEmpty)
    }

    func testOpenFilePresentsTheFileViewer() async {
        context.performTerminalLinkIntent(.openFile(repoPath: "/r/alpha", filePath: "src/App.swift"))

        let presented = await poll { if case .file = self.context.fileViewer.presentation { return true }; return false }
        XCTAssertTrue(presented, "FileViewer açılmadı: \(context.fileViewer.presentation)")
    }

    /// Popover'dan seçilen eylem hem kapanır hem de çalışır.
    func testRunningAnActionFromThePopoverClosesItAndRuns() {
        let action = TerminalLinkAction(
            slot: .alternate, title: "Open in Finder",
            intent: .revealInFinder(path: "/r/alpha")
        )

        context.terminalLinks.perform(action)

        XCTAssertNil(context.terminalLinks.request)
        XCTAssertEqual(fixture.recorder.revealedPaths, ["/r/alpha"])
    }

    private func poll(_ condition: @escaping () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
