import Foundation
import LumiKit
import XCTest
@testable import LumiState

/// FileViewerStore'un dosya türüne göre yönlendirmesi (karar 21): görseller
/// önizleme yoluna, metin/markdown mevcut diff yoluna gider.
@MainActor
final class FileViewerStoreTests: XCTestCase {
    private func makeStore(_ git: FakeGitService) -> FileViewerStore {
        FileViewerStore(git: git, toasts: ToastStore(autoDismissAfter: 60))
    }

    private let samplePreview = ImagePreview(
        filePath: "assets/logo.png",
        before: Data([1, 2, 3]),
        after: Data([4, 5, 6])
    )

    // MARK: - view modu

    func testPresentViewLoadsTextThroughReadFile() async {
        let git = FakeGitService()
        let store = makeStore(git)

        await store.presentView(repoPath: "/repo", filePath: "docs/readme.md")

        XCTAssertTrue(store.isPresented)
        XCTAssertEqual(store.mode, .view)
        XCTAssertEqual(store.previewKind, .markdown)
        XCTAssertNil(store.imagePreview)
        let readFileCalls = await git.readFileCalls
        XCTAssertEqual(readFileCalls, ["docs/readme.md"])
    }

    func testPresentViewUsesImagePreviewForImageFile() async {
        let git = FakeGitService()
        await git.setPreview(samplePreview)
        let store = makeStore(git)

        await store.presentView(repoPath: "/repo", filePath: "assets/logo.png")

        XCTAssertEqual(store.previewKind, .image)
        XCTAssertEqual(store.imagePreview, samplePreview)
        XCTAssertNil(store.fileContent)
        let readFileCalls = await git.readFileCalls
        XCTAssertTrue(readFileCalls.isEmpty)
        // view modunda karşılaştırma yok → sha nil (HEAD ↔ disk)
        let previewCalls = await git.imagePreviewCalls
        XCTAssertEqual(previewCalls, [.init(file: "assets/logo.png", sha: nil)])
    }

    // MARK: - diff modu

    func testPresentDiffUsesImagePreviewForImageFile() async {
        let git = FakeGitService()
        await git.setPreview(samplePreview)
        let store = makeStore(git)

        await store.presentDiff(repoPath: "/repo", filePath: "assets/logo.png")

        XCTAssertEqual(store.mode, .diff)
        XCTAssertEqual(store.imagePreview, samplePreview)
        XCTAssertNil(store.diff)
        let fileDiffCalls = await git.fileDiffCalls
        XCTAssertTrue(fileDiffCalls.isEmpty)
    }

    func testPresentDiffKeepsTextPathForNonImage() async {
        let git = FakeGitService()
        let store = makeStore(git)

        await store.presentDiff(repoPath: "/repo", filePath: "src/main.swift")

        XCTAssertNotNil(store.diff)
        XCTAssertNil(store.imagePreview)
        let fileDiffCalls = await git.fileDiffCalls
        XCTAssertEqual(fileDiffCalls, ["src/main.swift"])
    }

    // MARK: - commit-diff modu

    func testCommitFileSelectionSwitchesBetweenDiffAndPreview() async {
        let git = FakeGitService()
        await git.setPreview(samplePreview)
        await git.setCommitFiles([
            CommitFile(path: "docs/readme.md", status: .modified),
            CommitFile(path: "assets/logo.png", status: .modified),
        ])
        let store = makeStore(git)
        let commit = GitCommit(
            hash: "abc123def",
            shortHash: "abc123d",
            message: "change",
            author: "tester",
            date: Date(timeIntervalSince1970: 0)
        )

        await store.presentCommit(repoPath: "/repo", commit: commit)
        XCTAssertEqual(store.mode, .commitDiff)
        XCTAssertEqual(store.filePath, "docs/readme.md")
        XCTAssertNotNil(store.diff)
        XCTAssertNil(store.imagePreview)

        await store.selectCommitFile("assets/logo.png")
        XCTAssertEqual(store.imagePreview, samplePreview)
        XCTAssertNil(store.diff)
        // Commit modunda önizleme sha'ya bağlı (sha^ ↔ sha)
        let previewCalls = await git.imagePreviewCalls
        XCTAssertEqual(previewCalls, [.init(file: "assets/logo.png", sha: "abc123def")])
        // Dosya listesi ve commit context korunur
        XCTAssertEqual(store.commitContext?.files.count, 2)

        await store.selectCommitFile("docs/readme.md")
        XCTAssertNil(store.imagePreview)
        XCTAssertNotNil(store.diff)
    }

    // MARK: - Markdown toggle / kapanış

    func testMarkdownRenderingIsOnByDefaultAndTogglable() async {
        let store = makeStore(FakeGitService())
        XCTAssertTrue(store.rendersMarkdown)
        store.rendersMarkdown = false
        XCTAssertFalse(store.rendersMarkdown)
    }

    func testCloseClearsImagePreview() async {
        let git = FakeGitService()
        await git.setPreview(samplePreview)
        let store = makeStore(git)

        await store.presentView(repoPath: "/repo", filePath: "assets/logo.png")
        store.close()

        XCTAssertFalse(store.isPresented)
        XCTAssertNil(store.imagePreview)
        XCTAssertEqual(store.filePath, "")
    }
}
