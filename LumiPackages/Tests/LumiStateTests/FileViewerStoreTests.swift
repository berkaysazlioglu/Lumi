import Foundation
import LumiKit
import LumiTestSupport
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

    // MARK: - Hata yolları (KARAKTERİZASYON — mevcut davranış belgeleniyor)

    /// Karar 5 koridoru: okuma hatası toast'a düşer ve modal AÇILMAZ.
    func testPresentViewFailureShowsToastAndDoesNotPresent() async {
        let git = FakeGitService()
        await git.setError(.gitFailed(operation: "show", detail: "no such file"))
        let toasts = ToastStore(autoDismissAfter: 60)
        let store = FileViewerStore(git: git, toasts: toasts)

        await store.presentView(repoPath: "/repo", filePath: "missing.txt")

        XCTAssertFalse(store.isPresented)
        XCTAssertEqual(toasts.toasts.count, 1)
        XCTAssertEqual(store.filePath, "", "hatalı dosya adı state'e yazılmaz")
    }

    /// ŞÜPHELİ (bug adayı — Faz 5'te ele alınacak, burada yalnız BELGELENİR):
    /// açık bir dosya varken ikinci dosyanın okuması başarısız olursa modal
    /// ÖNCEKİ dosyanın adıyla ve ÖNCEKİ içeriğiyle açık kalır — kullanıcı yeni
    /// dosyayı açtığını sanabilir. Beklenen: ya modal kapanmalı ya da içerik
    /// "yüklenemedi" durumuna geçmeli.
    func testFailedSecondPresentLeavesPreviousFileVisible() async {
        let git = FakeGitService()
        await git.setFileContent("first content")
        let toasts = ToastStore(autoDismissAfter: 60)
        let store = FileViewerStore(git: git, toasts: toasts)

        await store.presentView(repoPath: "/repo", filePath: "a.txt")
        XCTAssertEqual(store.fileContent, "first content")

        await git.setError(.gitFailed(operation: "show", detail: "boom"))
        await store.presentView(repoPath: "/repo", filePath: "b.txt")

        XCTAssertTrue(store.isPresented, "modal açık KALIR")
        XCTAssertEqual(store.filePath, "a.txt", "eski dosya adı görünmeye devam eder")
        XCTAssertEqual(store.fileContent, "first content", "eski içerik ekranda kalır")
        XCTAssertEqual(toasts.toasts.count, 1, "hata en azından görünür kılınır")
    }

    /// Aynı karakterizasyon diff yolunda: başarısız diff önceki diff'i bırakır.
    func testFailedDiffLeavesPreviousDiffVisible() async {
        let git = FakeGitService()
        let diff = UnifiedDiff(filePath: "a.txt", isBinary: false, hunks: [])
        await git.setDiff(diff)
        let toasts = ToastStore(autoDismissAfter: 60)
        let store = FileViewerStore(git: git, toasts: toasts)

        await store.presentDiff(repoPath: "/repo", filePath: "a.txt")
        XCTAssertEqual(store.diff, diff)

        await git.setError(.gitFailed(operation: "diff", detail: "boom"))
        await store.presentDiff(repoPath: "/repo", filePath: "b.txt")

        XCTAssertEqual(store.filePath, "a.txt")
        XCTAssertEqual(store.diff, diff, "eski diff ekranda kalır")
    }

    /// Commit dosyası seçiminde hata: `diff` ÖNCE temizlendiği için ekran boşalır
    /// (yukarıdaki iki yoldan farklı davranış — tutarsızlık kaydı).
    func testFailedCommitFileSelectionClearsDiff() async {
        let git = FakeGitService()
        await git.setCommitFiles([
            CommitFile(path: "a.txt", status: .modified),
            CommitFile(path: "b.txt", status: .modified),
        ])
        let diff = UnifiedDiff(filePath: "a.txt", isBinary: false, hunks: [])
        await git.setDiff(diff)
        let toasts = ToastStore(autoDismissAfter: 60)
        let store = FileViewerStore(git: git, toasts: toasts)

        await store.presentCommit(
            repoPath: "/repo",
            commit: GitCommit(hash: "abcdef1234", shortHash: "abcdef1", message: "m", author: "a", date: Date())
        )
        XCTAssertEqual(store.diff, diff)

        await git.setError(.gitFailed(operation: "show", detail: "boom"))
        await store.selectCommitFile("b.txt")

        XCTAssertNil(store.diff, "commit yolunda eski diff KORUNMAZ")
        XCTAssertEqual(store.filePath, "b.txt", "dosya adı ise yeni dosyayı gösterir")
        XCTAssertFalse(store.isLoading)
        XCTAssertEqual(toasts.toasts.count, 1)
    }

    func testCommitWithNoFilesShowsInfoToastAndDoesNotPresent() async {
        let git = FakeGitService()
        await git.setCommitFiles([])
        let toasts = ToastStore(autoDismissAfter: 60)
        let store = FileViewerStore(git: git, toasts: toasts)

        await store.presentCommit(
            repoPath: "/repo",
            commit: GitCommit(hash: "abcdef1234", shortHash: "abcdef1", message: "m", author: "a", date: Date())
        )

        XCTAssertFalse(store.isPresented)
        XCTAssertEqual(toasts.toasts.first?.kind, .info)
        XCTAssertEqual(toasts.toasts.first?.title, "abcdef1")
    }

    func testSelectCommitFileWithoutContextIsNoop() async {
        let git = FakeGitService()
        let store = makeStore(git)
        await store.selectCommitFile("a.txt")

        XCTAssertEqual(store.filePath, "")
        let calls = await git.commitFileDiffCalls
        XCTAssertTrue(calls.isEmpty)
    }

    // MARK: - close() kısmi sıfırlama (karakterizasyon)

    /// `close()` `mode`, `repoPath` ve `rendersMarkdown`'ı SIFIRLAMAZ; bir
    /// sonraki sunuma kadar bayat kalırlar (her sunum yolu bunları yeniden
    /// yazdığı için bugün görünür bir etkisi yok — Faz 5.3 sum type'ı bunu
    /// yapısal olarak kaldıracak).
    func testCloseLeavesModeAndRepoPathStale() async {
        let git = FakeGitService()
        let store = makeStore(git)
        await store.presentDiff(repoPath: "/repo", filePath: "a.txt")
        store.rendersMarkdown = false

        store.close()

        XCTAssertFalse(store.isPresented)
        XCTAssertEqual(store.mode, .diff, "mode korunur")
        XCTAssertEqual(store.repoPath, "/repo", "repoPath korunur")
        XCTAssertFalse(store.rendersMarkdown, "markdown tercihi oturum boyunca sürer")
        XCTAssertNil(store.diff)
        XCTAssertNil(store.fileContent)
        XCTAssertNil(store.commitContext)
    }
}
