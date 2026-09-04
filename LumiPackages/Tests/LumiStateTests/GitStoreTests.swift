import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiState

/// GitStore yükleme davranışı — özellikle branch başına `git log` çağrılarının
/// eşzamanlılık tavanı (1.9: sınırsız TaskGroup her FSEvents tazelemesinde
/// N branch için N git süreci açıyordu).
@MainActor
final class GitStoreTests: XCTestCase {
    private let repoPath = "/tmp/lumi-git-store-test"

    private func makeStore(_ git: FakeGitService) -> GitStore {
        GitStore(git: git, toasts: ToastStore(autoDismissAfter: 60))
    }

    func testLoadAllCapsConcurrentCommitCalls() async {
        let git = FakeGitService()
        await git.setBranches((0 ..< 10).map { GitBranch(name: "b\($0)", isCurrent: $0 == 0) })
        await git.setCommitsDelay(.milliseconds(30))
        let store = makeStore(git)

        await store.loadAll(repoPath)

        let peak = await git.maxConcurrentCommitsCalls
        XCTAssertLessThanOrEqual(
            peak, GitStore.maxConcurrentBranchLoads,
            "eşzamanlı git log sayısı tavanı aştı: \(peak)"
        )
        XCTAssertGreaterThan(peak, 1, "sınır seri çalışmaya düşmemeli")
    }

    func testLoadAllQueriesEveryBranchExactlyOnce() async {
        let git = FakeGitService()
        await git.setBranches((0 ..< 10).map { GitBranch(name: "b\($0)", isCurrent: $0 == 0) })
        await git.setCommitsDelay(.milliseconds(5))
        let store = makeStore(git)

        await store.loadAll(repoPath)

        let calls = await git.commitsCallCount
        XCTAssertEqual(calls, 10)
        XCTAssertEqual(store.commitsByBranch[repoPath]?.count, 10)
    }

    func testLoadAllExpandsCurrentBranchUntilUserToggles() async {
        let git = FakeGitService()
        await git.setBranches([
            GitBranch(name: "main", isCurrent: true),
            GitBranch(name: "feature", isCurrent: false),
        ])
        let store = makeStore(git)

        await store.loadAll(repoPath)
        XCTAssertTrue(store.isBranchExpanded(repoPath, name: "main"))

        store.toggleBranch(repoPath, name: "main")
        await store.loadAll(repoPath)
        XCTAssertFalse(
            store.isBranchExpanded(repoPath, name: "main"),
            "kullanıcı toggle'ından sonra otomatik expand geri gelmemeli"
        )
    }

    func testAutoExpandTrackingIsPerRepo() async {
        let git = FakeGitService()
        await git.setBranches([GitBranch(name: "main", isCurrent: true)])
        let store = makeStore(git)

        await store.loadAll(repoPath)
        store.toggleBranch(repoPath, name: "main")

        await store.loadAll("/other-repo")
        XCTAssertTrue(
            store.isBranchExpanded("/other-repo", name: "main"),
            "bir repodaki toggle diğerinin auto-expand'ini kapatmaz"
        )
    }

    func testNoCurrentBranchMeansNoAutoExpand() async {
        let git = FakeGitService()
        await git.setBranches([GitBranch(name: "main", isCurrent: false)])
        let store = makeStore(git)

        await store.loadAll(repoPath)
        XCTAssertFalse(store.isBranchExpanded(repoPath, name: "main"))
    }

    func testToggleBranchIsSymmetric() async {
        let store = makeStore(FakeGitService())
        store.toggleBranch(repoPath, name: "feature")
        XCTAssertTrue(store.isBranchExpanded(repoPath, name: "feature"))
        store.toggleBranch(repoPath, name: "feature")
        XCTAssertFalse(store.isBranchExpanded(repoPath, name: "feature"))
    }

    // MARK: - Changes / seçim

    private let changes = [
        GitFileChange(path: "a.swift", status: .modified),
        GitFileChange(path: "b.swift", status: .added),
        GitFileChange(path: "c.swift", status: .deleted),
    ]

    func testLoadChangesSelectsEverythingByDefault() async {
        let git = FakeGitService()
        await git.setStatus(changes)
        let store = makeStore(git)

        await store.loadChanges(repoPath)
        XCTAssertEqual(store.changes[repoPath], changes)
        XCTAssertEqual(store.selectedFiles[repoPath], ["a.swift", "b.swift", "c.swift"])
    }

    /// Karakterizasyon: HER status yüklemesi seçimi sıfırlar — kullanıcının
    /// deselect ettiği dosyalar bir sonraki FSEvents tazelemesinde geri seçilir.
    /// (Şüpheli davranış; Faz 5'te ele alınacak — burada yalnız BELGELENİR.)
    func testReloadResetsUserDeselection() async {
        let git = FakeGitService()
        await git.setStatus(changes)
        let store = makeStore(git)

        await store.loadChanges(repoPath)
        store.toggleFile(repoPath, path: "a.swift")
        XCTAssertFalse(store.isSelected(repoPath, path: "a.swift"))

        await store.loadChanges(repoPath)
        XCTAssertTrue(
            store.isSelected(repoPath, path: "a.swift"),
            "select-all default her yüklemede geri gelir (mevcut davranış)"
        )
    }

    func testToggleSelectAllClearsWhenEverythingSelected() async {
        let git = FakeGitService()
        await git.setStatus(changes)
        let store = makeStore(git)
        await store.loadChanges(repoPath)

        store.toggleSelectAll(repoPath)
        XCTAssertEqual(store.selectedFiles[repoPath], [])
    }

    func testToggleSelectAllSelectsEverythingFromPartialSelection() async {
        let git = FakeGitService()
        await git.setStatus(changes)
        let store = makeStore(git)
        await store.loadChanges(repoPath)
        store.toggleFile(repoPath, path: "a.swift") // kısmi seçim

        store.toggleSelectAll(repoPath)
        XCTAssertEqual(store.selectedFiles[repoPath], ["a.swift", "b.swift", "c.swift"])
    }

    func testToggleSelectAllOnEmptyRepoIsNoop() {
        let store = makeStore(FakeGitService())
        store.toggleSelectAll(repoPath)
        // count == all.count (0 == 0) → boş küme; çökme yok, seçim boş kalır
        XCTAssertEqual(store.selectedFiles[repoPath], [])
    }

    func testToggleFileIsSymmetric() async {
        let git = FakeGitService()
        await git.setStatus(changes)
        let store = makeStore(git)
        await store.loadChanges(repoPath)

        store.toggleFile(repoPath, path: "b.swift")
        XCTAssertFalse(store.isSelected(repoPath, path: "b.swift"))
        store.toggleFile(repoPath, path: "b.swift")
        XCTAssertTrue(store.isSelected(repoPath, path: "b.swift"))
    }

    // MARK: - Commit

    private func makeCommitReadyStore(_ git: FakeGitService) async -> GitStore {
        await git.setStatus(changes)
        let store = GitStore(git: git, toasts: ToastStore(autoDismissAfter: 60))
        await store.loadChanges(repoPath)
        store.commitMessages[repoPath] = "feat: add"
        return store
    }

    func testCommitSendsSortedSelectionAndClearsMessage() async {
        let git = FakeGitService()
        let store = await makeCommitReadyStore(git)

        await store.commit(repoPath)

        let calls = await git.commitCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.message, "feat: add")
        XCTAssertEqual(calls.first?.files, ["a.swift", "b.swift", "c.swift"], "sıralı gönderilir")
        XCTAssertEqual(store.commitMessages[repoPath], "", "başarıda mesaj temizlenir")
        XCTAssertFalse(store.isCommitting)
    }

    func testSuccessfulCommitReloadsEverything() async {
        let git = FakeGitService()
        await git.setBranches([GitBranch(name: "main", isCurrent: true)])
        let store = await makeCommitReadyStore(git)
        let statusBefore = await git.statusCallCount

        await store.commit(repoPath)

        let statusAfter = await git.statusCallCount
        let branchCalls = await git.branchesCallCount
        XCTAssertGreaterThan(statusAfter, statusBefore, "commit sonrası loadAll → status yeniden çekilir")
        XCTAssertEqual(branchCalls, 1)
    }

    func testEmptyMessageBlocksCommit() async {
        let git = FakeGitService()
        let store = await makeCommitReadyStore(git)
        store.commitMessages[repoPath] = "   \n  " // yalnız whitespace

        await store.commit(repoPath)

        let calls = await git.commitCalls
        XCTAssertTrue(calls.isEmpty, "boş/whitespace mesaj commit etmez")
    }

    func testMissingMessageBlocksCommit() async {
        let git = FakeGitService()
        await git.setStatus(changes)
        let store = makeStore(git)
        await store.loadChanges(repoPath)

        await store.commit(repoPath) // commitMessages hiç yazılmadı
        let calls = await git.commitCalls
        XCTAssertTrue(calls.isEmpty)
    }

    func testNoSelectedFilesBlocksCommit() async {
        let git = FakeGitService()
        let store = await makeCommitReadyStore(git)
        store.toggleSelectAll(repoPath) // hepsini kaldır

        await store.commit(repoPath)

        let calls = await git.commitCalls
        XCTAssertTrue(calls.isEmpty, "dosya seçilmeden commit yok")
        XCTAssertEqual(store.commitMessages[repoPath], "feat: add", "mesaj korunur")
    }

    func testCommitMessageIsTrimmedBeforeSending() async {
        let git = FakeGitService()
        let store = await makeCommitReadyStore(git)
        store.commitMessages[repoPath] = "  fix: pad  "

        await store.commit(repoPath)
        let calls = await git.commitCalls
        XCTAssertEqual(calls.first?.message, "fix: pad")
    }

    func testCommitFailureShowsToastAndKeepsMessage() async {
        let git = FakeGitService()
        await git.setError(.gitFailed(operation: "commit", detail: "nothing to commit"))
        let toasts = ToastStore(autoDismissAfter: 60)
        await git.setStatus(changes)
        let store = GitStore(git: git, toasts: toasts)
        await store.loadChanges(repoPath)
        store.commitMessages[repoPath] = "feat: add"

        await store.commit(repoPath)

        XCTAssertEqual(toasts.toasts.count, 1, "karar 5: hata görünür")
        XCTAssertEqual(toasts.toasts.first?.kind, .error)
        XCTAssertEqual(store.commitMessages[repoPath], "feat: add", "hatada mesaj kaybolmaz")
        XCTAssertFalse(store.isCommitting, "isCommitting hata yolunda da düşer")
    }

    func testCanCommitReflectsInFlightState() {
        let store = makeStore(FakeGitService())
        XCTAssertTrue(store.canCommit)
    }

    // MARK: - refresh

    func testRefreshDelegatesToLoadAll() async {
        let git = FakeGitService()
        await git.setBranches([GitBranch(name: "main", isCurrent: true)])
        let store = makeStore(git)

        await store.refresh(repoPath)

        let branchCalls = await git.branchesCallCount
        let statusCalls = await git.statusCallCount
        XCTAssertEqual(branchCalls, 1)
        XCTAssertEqual(statusCalls, 1)
    }

    func testCachesAreKeyedPerRepo() async {
        let git = FakeGitService()
        await git.setStatus(changes)
        let store = makeStore(git)

        await store.loadChanges("/repo-a")
        await git.setStatus([])
        await store.loadChanges("/repo-b")

        XCTAssertEqual(store.changes["/repo-a"]?.count, 3)
        XCTAssertEqual(store.changes["/repo-b"]?.count, 0)
    }
}
