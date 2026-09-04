import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// FileViewerStore'un sum-type sunumu (refactor 5.3) + dosya türüne göre
/// yönlendirme (karar 21) + TEK hata kuralı (karar 5).
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

    private func commit(_ hash: String = "abc123def", short: String = "abc123d") -> GitCommit {
        GitCommit(
            hash: hash,
            shortHash: short,
            message: "change",
            author: "tester",
            date: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - view modu

    func testPresentViewLoadsTextThroughReadFile() async {
        let git = FakeGitService()
        await git.setFileContent("# hello")
        let store = makeStore(git)

        await store.presentView(repoPath: "/repo", filePath: "docs/readme.md")

        XCTAssertEqual(
            store.presentation,
            .file(
                repoPath: "/repo",
                filePath: "docs/readme.md",
                mode: .view,
                content: .loaded(.text("# hello"))
            )
        )
        XCTAssertTrue(store.isPresented)
        XCTAssertEqual(store.mode, .view)
        XCTAssertEqual(store.previewKind, .markdown)
        let readFileCalls = await git.readFileCalls
        XCTAssertEqual(readFileCalls, ["docs/readme.md"])
    }

    func testPresentViewUsesImagePreviewForImageFile() async {
        let git = FakeGitService()
        await git.setPreview(samplePreview)
        let store = makeStore(git)

        await store.presentView(repoPath: "/repo", filePath: "assets/logo.png")

        XCTAssertEqual(store.previewKind, .image)
        XCTAssertEqual(store.content, .loaded(.image(samplePreview)))
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
        XCTAssertEqual(store.content, .loaded(.image(samplePreview)))
        let fileDiffCalls = await git.fileDiffCalls
        XCTAssertTrue(fileDiffCalls.isEmpty)
    }

    func testPresentDiffKeepsTextPathForNonImage() async {
        let git = FakeGitService()
        let diff = UnifiedDiff(filePath: "src/main.swift", isBinary: false, hunks: [])
        await git.setDiff(diff)
        let store = makeStore(git)

        await store.presentDiff(repoPath: "/repo", filePath: "src/main.swift")

        XCTAssertEqual(store.content, .loaded(.diff(diff)))
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
        let diff = UnifiedDiff(filePath: "docs/readme.md", isBinary: false, hunks: [])
        await git.setDiff(diff)
        let store = makeStore(git)

        await store.presentCommit(repoPath: "/repo", commit: commit())
        XCTAssertEqual(store.mode, .commitDiff)
        XCTAssertEqual(store.filePath, "docs/readme.md")
        XCTAssertEqual(store.content, .loaded(.diff(diff)))

        await store.selectCommitFile("assets/logo.png")
        XCTAssertEqual(store.content, .loaded(.image(samplePreview)))
        // Commit modunda önizleme sha'ya bağlı (sha^ ↔ sha)
        let previewCalls = await git.imagePreviewCalls
        XCTAssertEqual(previewCalls, [.init(file: "assets/logo.png", sha: "abc123def")])
        // Dosya listesi ve commit context korunur
        XCTAssertEqual(store.commitContext?.files.count, 2)

        await store.selectCommitFile("docs/readme.md")
        XCTAssertEqual(store.content, .loaded(.diff(diff)))
    }

    func testCommitWithNoFilesShowsInfoToastAndDoesNotPresent() async {
        let git = FakeGitService()
        await git.setCommitFiles([])
        let toasts = ToastStore(autoDismissAfter: 60)
        let store = FileViewerStore(git: git, toasts: toasts)

        await store.presentCommit(repoPath: "/repo", commit: commit("abcdef1234", short: "abcdef1"))

        XCTAssertEqual(store.presentation, .hidden)
        XCTAssertEqual(toasts.toasts.first?.kind, .info)
        XCTAssertEqual(toasts.toasts.first?.title, "abcdef1")
    }

    func testSelectCommitFileWithoutContextIsNoop() async {
        let git = FakeGitService()
        let store = makeStore(git)
        await store.selectCommitFile("a.txt")

        XCTAssertEqual(store.presentation, .hidden)
        let calls = await git.commitFileDiffCalls
        XCTAssertTrue(calls.isEmpty)
    }

    // MARK: - Markdown toggle / kapanış

    func testMarkdownRenderingIsOnByDefaultAndTogglable() async {
        let store = makeStore(FakeGitService())
        XCTAssertTrue(store.rendersMarkdown)
        store.rendersMarkdown = false
        XCTAssertFalse(store.rendersMarkdown)
    }

    /// Render'lı markdown TÜREVDİR: dosya uzantısı + oturumluk tercih.
    func testIsRenderedMarkdownDerivesFromExtensionAndToggle() async {
        let git = FakeGitService()
        let store = makeStore(git)

        await store.presentView(repoPath: "/repo", filePath: "docs/readme.md")
        XCTAssertTrue(store.isRenderedMarkdown)

        store.rendersMarkdown = false
        XCTAssertFalse(store.isRenderedMarkdown)

        store.rendersMarkdown = true
        await store.presentView(repoPath: "/repo", filePath: "src/main.swift")
        XCTAssertFalse(store.isRenderedMarkdown, "markdown olmayan dosyada render yok")
    }

    /// `close()` TEK atamadır: sunum `.hidden` olur, tüm türevler sıfırlanır.
    /// (Eski modelde `mode`/`repoPath` bayat kalıyordu — sum type bunu kaldırdı.)
    func testCloseResetsEveryDerivedField() async {
        let git = FakeGitService()
        let store = makeStore(git)
        await store.presentDiff(repoPath: "/repo", filePath: "a.txt")
        store.rendersMarkdown = false

        store.close()

        XCTAssertEqual(store.presentation, .hidden)
        XCTAssertFalse(store.isPresented)
        XCTAssertEqual(store.repoPath, "")
        XCTAssertEqual(store.filePath, "")
        XCTAssertNil(store.commitContext)
        XCTAssertNil(store.content)
        XCTAssertFalse(store.rendersMarkdown, "markdown tercihi oturum boyunca sürer")
    }

    // MARK: - Yarış koruması

    /// Yavaş dönen ilk yükleme, kullanıcının bu arada açtığı yeni dosyayı EZMEZ
    /// (eski modelde alanlar sırasız yazılabiliyordu).
    func testStaleLoadDoesNotOverwriteNewerPresentation() async {
        let git = FakeGitService()
        await git.setReadFileDelay(.milliseconds(120))
        await git.setFileContent("slow content")
        let store = makeStore(git)

        let slow = Task { await store.presentView(repoPath: "/repo", filePath: "slow.txt") }
        await Task.yield()
        await git.setReadFileDelay(.zero)
        await git.setFileContent("fast content")
        await store.presentView(repoPath: "/repo", filePath: "fast.txt")
        await slow.value

        XCTAssertEqual(store.filePath, "fast.txt")
        XCTAssertEqual(store.content, .loaded(.text("fast content")))
    }

    // MARK: - Hata yolu: TEK kural (karar 5)

    /// Yükleme hatası → içerik `.failed` + toast; modal YENİ dosyanın adıyla
    /// açılır (eski davranış: hiç açılmıyordu).
    func testFailedLoadPresentsFailedContentAndToast() async {
        let git = FakeGitService()
        await git.setError(.gitFailed(operation: "show", detail: "no such file"))
        let toasts = ToastStore(autoDismissAfter: 60)
        let store = FileViewerStore(git: git, toasts: toasts)

        await store.presentView(repoPath: "/repo", filePath: "missing.txt")

        XCTAssertTrue(store.isPresented)
        XCTAssertEqual(store.filePath, "missing.txt")
        XCTAssertEqual(store.content, .failed("Git show failed: no such file"))
        XCTAssertEqual(toasts.toasts.count, 1)
    }

    /// Eski tutarsızlık #1 kalktı: başarısız ikinci dosya ÖNCEKİ içeriği
    /// ekranda bırakmaz.
    func testFailedSecondPresentNeverKeepsPreviousFileVisible() async {
        let git = FakeGitService()
        await git.setFileContent("first content")
        let toasts = ToastStore(autoDismissAfter: 60)
        let store = FileViewerStore(git: git, toasts: toasts)

        await store.presentView(repoPath: "/repo", filePath: "a.txt")
        XCTAssertEqual(store.content, .loaded(.text("first content")))

        await git.setError(.gitFailed(operation: "show", detail: "boom"))
        await store.presentView(repoPath: "/repo", filePath: "b.txt")

        XCTAssertEqual(store.filePath, "b.txt", "yeni dosya adı gösterilir")
        XCTAssertEqual(store.content, .failed("Git show failed: boom"))
        XCTAssertNil(store.content?.value, "eski içerik ekranda kalmaz")
        XCTAssertEqual(toasts.toasts.count, 1)
    }

    /// Eski tutarsızlık #2 kalktı: diff yolu da aynı kurala uyar.
    func testFailedDiffDoesNotKeepPreviousDiffVisible() async {
        let git = FakeGitService()
        let diff = UnifiedDiff(filePath: "a.txt", isBinary: false, hunks: [])
        await git.setDiff(diff)
        let toasts = ToastStore(autoDismissAfter: 60)
        let store = FileViewerStore(git: git, toasts: toasts)

        await store.presentDiff(repoPath: "/repo", filePath: "a.txt")
        XCTAssertEqual(store.content, .loaded(.diff(diff)))

        await git.setError(.gitFailed(operation: "diff", detail: "boom"))
        await store.presentDiff(repoPath: "/repo", filePath: "b.txt")

        XCTAssertEqual(store.filePath, "b.txt")
        XCTAssertEqual(store.content, .failed("Git diff failed: boom"))
    }

    /// Eski tutarsızlık #3 kalktı: commit yolu artık boş ekran değil, aynı
    /// `.failed` durumunu gösterir.
    func testFailedCommitFileSelectionShowsFailedContent() async {
        let git = FakeGitService()
        await git.setCommitFiles([
            CommitFile(path: "a.txt", status: .modified),
            CommitFile(path: "b.txt", status: .modified),
        ])
        let diff = UnifiedDiff(filePath: "a.txt", isBinary: false, hunks: [])
        await git.setDiff(diff)
        let toasts = ToastStore(autoDismissAfter: 60)
        let store = FileViewerStore(git: git, toasts: toasts)

        await store.presentCommit(repoPath: "/repo", commit: commit("abcdef1234", short: "abcdef1"))
        XCTAssertEqual(store.content, .loaded(.diff(diff)))

        await git.setError(.gitFailed(operation: "show", detail: "boom"))
        await store.selectCommitFile("b.txt")

        XCTAssertEqual(store.filePath, "b.txt")
        XCTAssertEqual(store.content, .failed("Git show failed: boom"))
        XCTAssertFalse(store.isLoading)
        XCTAssertEqual(store.commitContext?.files.count, 2, "commit bağlamı korunur")
        XCTAssertEqual(toasts.toasts.count, 1)
    }

    /// Commit yükleme hatasında commit sunumu bozulmaz — yalnız içerik `.failed`.
    func testFailedCommitSelectionKeepsCommitPresentation() async {
        let git = FakeGitService()
        await git.setCommitFiles([CommitFile(path: "a.txt", status: .modified)])
        await git.setError(.gitFailed(operation: "show", detail: "boom"))
        let store = makeStore(git)

        await store.presentCommit(repoPath: "/repo", commit: commit())

        guard case .commit(let repoPath, let context, let filePath, let content) = store.presentation
        else { return XCTFail("commit sunumu bekleniyordu") }
        XCTAssertEqual(repoPath, "/repo")
        XCTAssertEqual(context.shortSha, "abc123d")
        XCTAssertEqual(filePath, "a.txt")
        XCTAssertEqual(content, .failed("Git show failed: boom"))
    }
}
