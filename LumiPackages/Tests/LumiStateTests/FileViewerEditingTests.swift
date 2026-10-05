import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Karar 110: FileViewer'da düzenleme — taslak, kaydetme, disk çakışması ve
/// kaydedilmemiş taslakla geçiş onayı.
@MainActor
final class FileViewerEditingTests: XCTestCase {
    private func makeStore(content: String = "let a = 1\n") async -> (FileViewerStore, FakeGitService, ToastStore) {
        let git = FakeGitService()
        await git.setFileContent(content)
        let toasts = ToastStore(autoDismissAfter: 60)
        return (FileViewerStore(git: git, toasts: toasts), git, toasts)
    }

    func testDraftAppearsOnEditAndDropsWhenTextReturnsToDisk() async {
        let (store, _, _) = await makeStore()
        await store.presentView(repoPath: "/repo", filePath: "a.swift")
        XCTAssertTrue(store.isEditable)

        store.updateDraft("let a = 2\n")
        XCTAssertTrue(store.hasUnsavedChanges)
        XCTAssertEqual(store.displayedText, "let a = 2\n")

        store.updateDraft("let a = 1\n")
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    func testSaveWritesDraftAndMakesItTheNewBase() async {
        let (store, git, _) = await makeStore()
        await store.presentView(repoPath: "/repo", filePath: "a.swift")
        let revision = store.editorRevision
        store.updateDraft("let a = 2\n")

        let saved = await store.save()

        XCTAssertTrue(saved)
        let writes = await git.writeFileCalls
        XCTAssertEqual(writes, [.init(file: "a.swift", contents: "let a = 2\n")])
        XCTAssertFalse(store.hasUnsavedChanges)
        XCTAssertEqual(store.loadedText, "let a = 2\n")
        XCTAssertEqual(store.editorRevision, revision, "editör metni yeniden basılmaz")
    }

    func testSaveRefusesWhenFileChangedOnDiskThenOverwriteWrites() async {
        let (store, git, _) = await makeStore()
        await store.presentView(repoPath: "/repo", filePath: "a.swift")
        store.updateDraft("mine\n")
        await git.setFileContent("agent edit\n")

        let saved = await store.save()

        XCTAssertFalse(saved)
        XCTAssertEqual(store.saveState, .conflict)
        let refusedWrites = await git.writeFileCalls
        XCTAssertTrue(refusedWrites.isEmpty, "çakışmada diske yazılmaz")
        XCTAssertTrue(store.hasUnsavedChanges)

        let overwritten = await store.save(overwrite: true)
        XCTAssertTrue(overwritten)
        XCTAssertEqual(store.saveState, .idle)
        let content = await git.fileContent
        XCTAssertEqual(content, "mine\n")
    }

    func testReloadFromDiskDropsDraftAndLoadsNewContent() async {
        let (store, git, _) = await makeStore()
        await store.presentView(repoPath: "/repo", filePath: "a.swift")
        store.updateDraft("mine\n")
        await git.setFileContent("agent edit\n")
        _ = await store.save()

        await store.reloadFromDisk()

        XCTAssertFalse(store.hasUnsavedChanges)
        XCTAssertEqual(store.saveState, .idle)
        XCTAssertEqual(store.loadedText, "agent edit\n")
    }

    func testFailedWriteKeepsDraftAndShowsToast() async {
        let (store, git, toasts) = await makeStore()
        await store.presentView(repoPath: "/repo", filePath: "a.swift")
        store.updateDraft("mine\n")
        await git.setWriteError(.fileOperationFailed(path: "a.swift", detail: "read-only volume"))

        let saved = await store.save()

        XCTAssertFalse(saved)
        XCTAssertTrue(store.hasUnsavedChanges)
        XCTAssertEqual(store.saveState, .idle)
        XCTAssertEqual(toasts.toasts.count, 1)
    }

    func testCloseWithDraftAsksAndDiscardCloses() async {
        let (store, _, _) = await makeStore()
        await store.presentView(repoPath: "/repo", filePath: "a.swift")
        store.updateDraft("mine\n")

        store.close()
        XCTAssertTrue(store.isPresented, "taslak varken kapanmaz")
        XCTAssertTrue(store.isConfirmingDiscard)

        await store.confirmDiscard()
        XCTAssertFalse(store.isPresented)
        XCTAssertFalse(store.isConfirmingDiscard)
    }

    func testCancelKeepsDraftAndViewer() async {
        let (store, _, _) = await makeStore()
        await store.presentView(repoPath: "/repo", filePath: "a.swift")
        store.updateDraft("mine\n")
        store.close()

        store.cancelDiscard()

        XCTAssertTrue(store.isPresented)
        XCTAssertEqual(store.draft, "mine\n")
    }

    func testSaveAndContinueSavesThenOpensRequestedFile() async {
        let (store, git, _) = await makeStore()
        await store.presentView(repoPath: "/repo", filePath: "a.swift")
        store.updateDraft("mine\n")

        await store.presentView(repoPath: "/repo", filePath: "b.swift")
        XCTAssertEqual(store.filePath, "a.swift", "geçiş onay bekler")

        await store.saveAndContinue()

        let writes = await git.writeFileCalls
        XCTAssertEqual(writes.map(\.file), ["a.swift"])
        XCTAssertEqual(store.filePath, "b.swift")
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    func testRenderedMarkdownIsNotEditableButRawIs() async {
        let (store, _, _) = await makeStore(content: "# Title\n")
        await store.presentView(repoPath: "/repo", filePath: "README.md")
        XCTAssertFalse(store.isEditable, "Preview'da düzenleme yok")

        store.rendersMarkdown = false
        XCTAssertTrue(store.isEditable)
    }

    func testDiffAndLossyTextAreReadOnly() async {
        let (store, _, _) = await makeStore(content: "caf\u{FFFD}\n")
        await store.presentView(repoPath: "/repo", filePath: "latin1.txt")
        XCTAssertFalse(store.isEditable, "UTF-8 olmayan dosyayı yazmak onu bozardı")

        await store.presentDiff(repoPath: "/repo", filePath: "a.swift")
        XCTAssertFalse(store.isEditable)
        store.updateDraft("x")
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    func testMentionIsHiddenWhileDraftIsUnsaved() async {
        let (store, _, _) = await makeStore(content: "a\nb\n")
        await store.presentView(repoPath: "/repo", filePath: "a.swift")
        store.selectedLines = 1...1
        XCTAssertNotNil(store.mentionReference)

        store.updateDraft("a\nb\nc\n")
        XCTAssertNil(store.mentionReference, "ajan diski okur, satırlar kaymış olabilir")
    }
}
