import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Karar 57: jest → (popover | doğrudan eylem) ve hedefe göre eylem seçimi.
@MainActor
final class TerminalLinkActionStoreTests: XCTestCase {
    private let project = Repo(name: "Game", path: "/projects/game", isGitRepo: true, source: .standalone)
    private let workspace = ProjectWorkspace(
        projectPath: "/projects/game", path: "/workspaces/review", name: "Review",
        branch: "review", scm: .git
    )
    private var terminals: TerminalListStore!
    private var repos: RepoStore!
    private var workspaces: ProjectWorkspaceStore!
    private var store: TerminalLinkActionStore!
    private var intents: [TerminalLinkIntent] = []
    private var terminalID = TerminalID()

    override func setUp() async throws {
        let service = FakeTerminalService()
        terminals = TerminalListStore(service: service, toasts: ToastStore(autoDismissAfter: 60))
        let repoService = FakeRepoService()
        await repoService.setRepos([project])
        repos = RepoStore(service: repoService)
        await repos.reload()
        workspaces = ProjectWorkspaceStore(
            service: FakeWorkspaceService(), config: FakeConfigService(),
            repos: repos, toasts: ToastStore()
        )
        workspaces.updateRecords([workspace])

        let meta = try service.spawn(repoPath: project.path, task: nil, command: nil)
        terminalID = meta.id
        terminals.apply(.spawned(meta))

        intents = []
        store = TerminalLinkActionStore(
            terminals: terminals, repos: repos, workspaces: workspaces,
            homeDirectory: "/Users/dev",
            pathKind: { path in path.hasSuffix("/logs") ? .directory : .file }
        )
        store.onIntent = { [weak self] in self?.intents.append($0) }
    }

    private func activate(_ link: String, _ gesture: TerminalLinkGesture) async {
        await store.handle(TerminalLinkActivation(
            terminalID: terminalID, link: link, gesture: gesture, anchor: CGPoint(x: 8, y: 9)
        ))
    }

    // MARK: - Jestler

    func testPlainClickOpensPopoverWithoutRunningAnything() async {
        await activate("src/App.swift", .actions)

        XCTAssertEqual(store.request?.destination, "/projects/game/src/App.swift")
        XCTAssertEqual(store.request?.anchor, CGPoint(x: 8, y: 9))
        XCTAssertEqual(store.request?.terminalID, terminalID, "odak iadesi için terminal kimliği taşınmalı")
        XCTAssertEqual(store.request?.primary.title, "Open in Lumi")
        XCTAssertEqual(store.request?.alternate?.title, "Open in Finder")
        XCTAssertTrue(intents.isEmpty, "popover açılırken eylem çalışmamalı")
    }

    /// Popover'ın kendi ipucu "⌘ Click → birincil eylem" diyor: dosyada da
    /// doğrudan çalışır, sormaz. Seçim sorusu DÜZ tıkın işidir.
    func testCommandClickRunsPrimaryOnFilesToo() async {
        await activate("src/App.swift", .primary)

        XCTAssertNil(store.request)
        XCTAssertEqual(intents, [.openFile(repoPath: "/projects/game", filePath: "src/App.swift")])
    }

    func testCommandClickRunsPrimaryForNonFileTargets() async {
        await activate("/workspaces/review", .primary)

        XCTAssertNil(store.request)
        XCTAssertEqual(intents, [.switchWorkspace(path: "/workspaces/review")])
    }

    func testShiftCommandClickRunsAlternate() async {
        await activate("src/App.swift", .alternate)

        XCTAssertEqual(intents, [.revealInFinder(path: "/projects/game/src/App.swift")])
    }

    /// Alternatifi olmayan hedefte ⇧⌘ birincil eylemi işletir.
    func testShiftCommandFallsBackToPrimaryWhenThereIsNoAlternate() async {
        await activate("https://lumi.dev", .alternate)

        XCTAssertEqual(intents, [.openURL(URL(string: "https://lumi.dev")!)])
    }

    func testUnresolvableLinkOpensNothing() async {
        await activate("mailto:a@b.com", .actions)

        XCTAssertNil(store.request)
        XCTAssertTrue(intents.isEmpty)
    }

    // MARK: - Hedefe göre eylemler

    func testWorkspaceRootOffersSwitchAndFinder() async {
        await activate("/workspaces/review", .actions)

        XCTAssertEqual(store.request?.primary.intent, .switchWorkspace(path: "/workspaces/review"))
        XCTAssertEqual(store.request?.alternate?.intent, .revealInFinder(path: "/workspaces/review"))
        XCTAssertEqual(store.request?.primary.shortcutKeys, ["⌘", "Click"])
        XCTAssertEqual(store.request?.alternate?.shortcutKeys, ["⇧", "⌘", "Click"])
    }

    func testProjectRootIsAlsoAWorkspaceTarget() async {
        await activate("/projects/game", .actions)

        XCTAssertEqual(store.request?.primary.intent, .switchWorkspace(path: "/projects/game"))
    }

    func testDirectoryOutsideKnownRootsOnlyRevealsInFinder() async {
        await activate("/tmp/logs", .actions)

        XCTAssertEqual(store.request?.primary.intent, .revealInFinder(path: "/tmp/logs"))
        XCTAssertNil(store.request?.alternate)
    }

    /// Bilinen kökün dışındaki dosya FileViewer'a değil sistem uygulamasına gider.
    func testFileOutsideKnownRootsUsesDefaultApp() async {
        await activate("/tmp/report.pdf", .actions)

        XCTAssertEqual(store.request?.primary.intent, .openWithDefaultApp(path: "/tmp/report.pdf"))
        XCTAssertEqual(store.request?.alternate?.intent, .revealInFinder(path: "/tmp/report.pdf"))
        XCTAssertNil(store.request?.extra)
    }

    /// Kök içindeki dosyada üçüncü satır: FileViewer'ın gösteremediği türler
    /// (PDF, görsel, ofis) için sistem uygulaması.
    func testFileInsideRootOffersLumiFinderAndDefaultApp() async {
        await activate("docs/plan.pdf", .actions)

        XCTAssertEqual(store.request?.actions.map(\.title), [
            "Open in Lumi", "Open in Finder", "Open with default app",
        ])
        XCTAssertEqual(store.request?.extra?.shortcutKeys, [], "üçüncü satırın kısayolu yok")
    }

    /// Güvenlik: `NSWorkspace.open` bir `.command` dosyasını ÇALIŞTIRIR —
    /// terminale basılan metin güvenilmez bir kaynaktır.
    func testExecutableFileNeverOffersDefaultApp() async {
        await activate("/tmp/setup.command", .actions)

        XCTAssertEqual(store.request?.primary.intent, .revealInFinder(path: "/tmp/setup.command"))
        XCTAssertNil(store.request?.alternate)
        XCTAssertNil(store.request?.extra)
    }

    func testExecutableFileInsideRootOnlyDropsTheDefaultAppRow() async {
        await activate("scripts/install.sh", .actions)

        XCTAssertEqual(store.request?.actions.map(\.title), ["Open in Lumi", "Open in Finder"])
    }

    // MARK: - Karar 116

    /// HTML kök içinde: Lumi birincil, ⇧⌘ sistem tarayıcısı, Finder üçüncü satır.
    func testHTMLInsideRootOffersBrowserAsAlternate() async {
        await activate("dist/index.html", .actions)

        XCTAssertEqual(store.request?.actions.map(\.title), ["Open in Lumi", "Open in Browser", "Open in Finder"])
        XCTAssertEqual(store.request?.alternate?.intent, .openInBrowser(path: "/projects/game/dist/index.html"))
    }

    func testHTMLOutsideRootOpensInBrowserFirst() async {
        await activate("file:///tmp/report.HTM", .primary)

        XCTAssertEqual(intents, [.openInBrowser(path: "/tmp/report.HTM")])
    }

    /// Diskte olmayan yol popover açmaz, eylem de çalıştırmaz.
    func testMissingPathOpensNothing() async {
        let strict = TerminalLinkActionStore(
            terminals: terminals, repos: repos, workspaces: workspaces,
            homeDirectory: "/Users/dev", pathKind: { _ in .missing }
        )
        var seen: [TerminalLinkIntent] = []
        strict.onIntent = { seen.append($0) }

        await strict.handle(TerminalLinkActivation(
            terminalID: terminalID, link: "build/out.o", gesture: .actions, anchor: .zero
        ))
        await strict.handle(TerminalLinkActivation(
            terminalID: terminalID, link: "build/out.o", gesture: .primary, anchor: .zero
        ))

        XCTAssertNil(strict.request)
        XCTAssertTrue(seen.isEmpty)
    }

    /// Diskin cevabı gelmezse (asılı ağ mount'u) tık süresiz beklemez.
    func testHangingPathProbeFallsBackInsteadOfBlocking() async {
        let slow = TerminalLinkActionStore(
            terminals: terminals, repos: repos, workspaces: workspaces,
            homeDirectory: "/Users/dev",
            pathKind: { _ in Thread.sleep(forTimeInterval: 3); return .directory }
        )
        var seen: [TerminalLinkIntent] = []
        slow.onIntent = { seen.append($0) }

        await slow.handle(TerminalLinkActivation(
            terminalID: terminalID, link: "/mnt/hang/file.txt",
            gesture: .actions, anchor: .zero
        ))

        XCTAssertNotNil(slow.request, "zaman aşımında da bir sonuç üretilmeli")
        XCTAssertEqual(slow.request?.target, .file(path: "/mnt/hang/file.txt"))
        XCTAssertTrue(seen.isEmpty)
    }

    func testOnlyURLsShowTheCopyButton() async {
        await activate("https://lumi.dev", .actions)
        XCTAssertEqual(store.request?.isCopyable, true)

        await activate("src/App.swift", .actions)
        XCTAssertEqual(store.request?.isCopyable, false)
    }

    // MARK: - Kapanış

    func testPerformClosesPopoverAndEmitsIntent() async throws {
        await activate("src/App.swift", .actions)
        let primary = try XCTUnwrap(store.request?.primary)

        store.perform(primary)

        XCTAssertNil(store.request)
        XCTAssertEqual(intents, [.openFile(repoPath: "/projects/game", filePath: "src/App.swift")])
    }

    func testDismissClosesPopover() async {
        await activate("src/App.swift", .actions)
        store.dismiss()

        XCTAssertNil(store.request)
        XCTAssertTrue(intents.isEmpty)
    }
}
