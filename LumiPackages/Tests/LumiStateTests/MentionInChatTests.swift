import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Karar 100 "Mention in Chat": hedef terminal çözümü, yapıştırma ve
/// FileViewer seçim durumunun ömrü.
@MainActor
final class MentionInChatTests: XCTestCase {
    private var service: FakeTerminalService!
    private var store: TerminalListStore!

    override func setUp() async throws {
        service = FakeTerminalService()
        store = TerminalListStore(service: service, toasts: ToastStore(autoDismissAfter: 60))
    }

    private func makeTerminal(_ name: String, repo: String = "/repo", provider: AgentProvider? = .claude) -> TerminalMeta {
        let meta = TerminalMeta(id: TerminalID(), name: name, repoPath: repo, createdAt: Date(), provider: provider)
        store.apply(.spawned(meta))
        return meta
    }

    // MARK: - Hedefler

    func testTargetsAreOnlyAgentTerminalsOfTheRepo() {
        let shell = makeTerminal("shell", provider: nil)
        let claude = makeTerminal("claude")
        let codex = makeTerminal("codex", provider: .codex)
        _ = makeTerminal("other", repo: "/other")
        store.focus(shell.id)

        XCTAssertEqual(store.mentionTargets(in: "/repo").map(\.id), [claude.id, codex.id])
    }

    func testActiveAgentTerminalComesFirst() {
        let first = makeTerminal("a")
        let second = makeTerminal("b")
        store.focus(second.id)

        XCTAssertEqual(store.mentionTargets(in: "/repo").map(\.id), [second.id, first.id])
    }

    func testLastActiveOfRepoWinsWhenAnotherRepoIsActive() {
        let first = makeTerminal("a")
        let second = makeTerminal("b")
        let elsewhere = makeTerminal("x", repo: "/other")
        store.focus(second.id)
        store.focus(elsewhere.id)

        XCTAssertEqual(store.mentionTargets(in: "/repo").map(\.id), [second.id, first.id])
    }

    func testMinimizedAgentIsStillATarget() {
        let only = makeTerminal("a")
        store.minimize(only.id)

        XCTAssertEqual(store.mentionTargets(in: "/repo").map(\.id), [only.id])
    }

    // MARK: - Yapıştırma

    func testPasteWritesBracketedTextWithoutSubmit() {
        let target = makeTerminal("a")

        XCTAssertTrue(store.paste("@a.cs#L1-2 ", into: target.id))

        XCTAssertEqual(service.writtenTexts.map(\.1), ["\u{1B}[200~@a.cs#L1-2 \u{1B}[201~"])
        XCTAssertFalse(service.writtenTexts[0].1.hasSuffix("\r"))
    }

    func testFailedPasteReportsFalse() {
        let target = makeTerminal("a")
        service.failWrites = true

        XCTAssertFalse(store.paste("@a#L1 ", into: target.id))
    }

    // MARK: - FileViewer seçimi

    private func makeViewer(content: String = "a\nb\nc\n") async -> (FileViewerStore, FakeGitService) {
        let git = FakeGitService()
        await git.setFileContent(content)
        return (FileViewerStore(git: git, toasts: ToastStore(autoDismissAfter: 60)), git)
    }

    func testReferenceExistsOnlyForSelectedTextInViewMode() async {
        let (viewer, _) = await makeViewer()
        await viewer.presentView(repoPath: "/repo", filePath: "src/a.cs")
        XCTAssertNil(viewer.mentionReference)

        viewer.selectedLines = 2...3

        XCTAssertEqual(viewer.mentionReference, "@src/a.cs#L2-3 ")
    }

    func testDiffAndRenderedMarkdownHaveNoReference() async {
        let (viewer, _) = await makeViewer()
        await viewer.presentView(repoPath: "/repo", filePath: "docs/readme.md")
        viewer.selectedLines = 1...1
        XCTAssertNil(viewer.mentionReference, "render'lı markdown satırları dosyaya eşlenmez")
        viewer.rendersMarkdown = false
        XCTAssertEqual(viewer.mentionReference, "@docs/readme.md#L1 ")

        await viewer.presentDiff(repoPath: "/repo", filePath: "src/a.cs")
        viewer.selectedLines = 1...1
        XCTAssertNil(viewer.mentionReference)
    }

    func testSelectionResetsWhenFileChangesOrViewerCloses() async {
        let (viewer, _) = await makeViewer()
        await viewer.presentView(repoPath: "/repo", filePath: "src/a.cs")
        viewer.selectedLines = 1...2

        await viewer.presentView(repoPath: "/repo", filePath: "src/b.cs")
        XCTAssertNil(viewer.selectedLines)

        viewer.selectedLines = 1...2
        viewer.close()
        XCTAssertNil(viewer.selectedLines)
    }
}
