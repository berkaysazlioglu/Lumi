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

    /// Faz 5 bug fix'i (eski `testReloadResetsUserDeselection`'ın tersi):
    /// kullanıcı deselect ettiyse FSEvents tazelemesi seçimi GERİ GETİRMEZ —
    /// aksi halde commit ekranında istenmeyen dosya stage edilebiliyordu.
    func testReloadPreservesUserDeselection() async {
        let git = FakeGitService()
        await git.setStatus(changes)
        let store = makeStore(git)

        await store.loadChanges(repoPath)
        store.toggleFile(repoPath, path: "a.swift")
        XCTAssertFalse(store.isSelected(repoPath, path: "a.swift"))

        await store.loadChanges(repoPath)
        XCTAssertFalse(
            store.isSelected(repoPath, path: "a.swift"),
            "kullanıcı seçimi tazelemede korunur"
        )
        XCTAssertEqual(store.selectedFiles[repoPath], ["b.swift", "c.swift"])
    }

    func testReloadKeepsSelectAllWhenUserNeverToggled() async {
        let git = FakeGitService()
        await git.setStatus(changes)
        let store = makeStore(git)

        await store.loadChanges(repoPath)
        await store.loadChanges(repoPath)

        XCTAssertEqual(
            store.selectedFiles[repoPath], ["a.swift", "b.swift", "c.swift"],
            "hiç toggle yoksa select-all default sürer"
        )
    }

    func testReloadDropsVanishedFilesFromUserSelection() async {
        let git = FakeGitService()
        await git.setStatus(changes)
        let store = makeStore(git)
        await store.loadChanges(repoPath)
        store.toggleFile(repoPath, path: "c.swift") // kullanıcı seçimi devreye girer

        await git.setStatus([GitFileChange(path: "a.swift", status: .modified)])
        await store.loadChanges(repoPath)

        XCTAssertEqual(store.selectedFiles[repoPath], ["a.swift"], "kaybolan dosyalar seçimden düşer")
    }

    func testReloadDoesNotSelectNewFilesAfterUserToggle() async {
        let git = FakeGitService()
        await git.setStatus(changes)
        let store = makeStore(git)
        await store.loadChanges(repoPath)
        store.toggleFile(repoPath, path: "a.swift")

        await git.setStatus(changes + [GitFileChange(path: "d.swift", status: .added)])
        await store.loadChanges(repoPath)

        XCTAssertFalse(store.isSelected(repoPath, path: "d.swift"), "yeni dosya kendiliğinden seçilmez")
        XCTAssertEqual(store.selectedFiles[repoPath], ["b.swift", "c.swift"])
    }

    func testUserSelectionTrackingIsPerRepo() async {
        let git = FakeGitService()
        await git.setStatus(changes)
        let store = makeStore(git)
        await store.loadChanges("/repo-a")
        store.toggleFile("/repo-a", path: "a.swift")

        await store.loadChanges("/repo-b")
        XCTAssertEqual(
            store.selectedFiles["/repo-b"], ["a.swift", "b.swift", "c.swift"],
            "bir repodaki toggle diğerinin select-all default'unu kapatmaz"
        )
    }

    // MARK: - Eviction (refactor 5.5)

    func testEvictClearsEveryPerRepoCache() async {
        let git = FakeGitService()
        await git.setBranches([GitBranch(name: "main", isCurrent: true)])
        await git.setStatus(changes)
        let store = makeStore(git)
        await store.loadAll(repoPath)
        store.setCommitMessage("wip", for: repoPath)
        store.toggleFile(repoPath, path: "a.swift")

        store.evict(repoPath)

        XCTAssertNil(store.branches[repoPath])
        XCTAssertNil(store.commitsByBranch[repoPath])
        XCTAssertNil(store.changes[repoPath])
        XCTAssertNil(store.selectedFiles[repoPath])
        XCTAssertNil(store.expandedBranches[repoPath])
        XCTAssertEqual(store.commitMessage(for: repoPath), "")
    }

    func testEvictResetsUserSelectionTracking() async {
        let git = FakeGitService()
        await git.setStatus(changes)
        let store = makeStore(git)
        await store.loadChanges(repoPath)
        store.toggleFile(repoPath, path: "a.swift")

        store.evict(repoPath)
        await store.loadChanges(repoPath)

        XCTAssertEqual(
            store.selectedFiles[repoPath], ["a.swift", "b.swift", "c.swift"],
            "eviction sonrası taze repo gibi davranır"
        )
    }

    func testEvictIsScopedToOneRepo() async {
        let git = FakeGitService()
        await git.setStatus(changes)
        let store = makeStore(git)
        await store.loadChanges("/repo-a")
        await store.loadChanges("/repo-b")

        store.evict("/repo-a")

        XCTAssertNil(store.changes["/repo-a"])
        XCTAssertEqual(store.changes["/repo-b"]?.count, 3)
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
        store.setCommitMessage("feat: add", for: repoPath)
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
        XCTAssertEqual(store.commitMessage(for: repoPath), "", "başarıda mesaj temizlenir")
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
        store.setCommitMessage("   \n  ", for: repoPath) // yalnız whitespace

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
        XCTAssertEqual(store.commitMessage(for: repoPath), "feat: add", "mesaj korunur")
    }

    func testCommitMessageIsTrimmedBeforeSending() async {
        let git = FakeGitService()
        let store = await makeCommitReadyStore(git)
        store.setCommitMessage("  fix: pad  ", for: repoPath)

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
        store.setCommitMessage("feat: add", for: repoPath)

        await store.commit(repoPath)

        XCTAssertEqual(toasts.toasts.count, 1, "karar 5: hata görünür")
        XCTAssertEqual(toasts.toasts.first?.kind, .error)
        XCTAssertEqual(store.commitMessage(for: repoPath), "feat: add", "hatada mesaj kaybolmaz")
        XCTAssertFalse(store.isCommitting, "isCommitting hata yolunda da düşer")
    }

    // MARK: - canCommit (refactor 6.7: view kuralı store'a taşındı)

    func testCanCommitRequiresSelectionAndMessage() async {
        let git = FakeGitService()
        let store = await makeCommitReadyStore(git)

        XCTAssertTrue(store.canCommit(repoPath))
    }

    func testCanCommitFalseWithoutMessage() async {
        let git = FakeGitService()
        await git.setStatus(changes)
        let store = makeStore(git)
        await store.loadChanges(repoPath)

        XCTAssertFalse(store.canCommit(repoPath), "mesaj yokken commit yok")
    }

    func testCanCommitFalseForWhitespaceOnlyMessage() async {
        let git = FakeGitService()
        let store = await makeCommitReadyStore(git)
        store.setCommitMessage("   \n  ", for: repoPath)

        XCTAssertFalse(store.canCommit(repoPath))
    }

    func testCanCommitFalseWithoutSelectedFiles() async {
        let git = FakeGitService()
        let store = await makeCommitReadyStore(git)
        store.toggleSelectAll(repoPath) // seçimi tamamen kaldır

        XCTAssertFalse(store.canCommit(repoPath))
    }

    func testCanCommitFalseWhileCommitInFlight() async {
        let git = FakeGitService()
        await git.setBranches([GitBranch(name: "main", isCurrent: true)])
        // commit sonrası loadAll'ın `git log` adımını askıda tutar: isCommitting
        // bu pencerede hâlâ true (defer fonksiyon çıkışında düşer).
        await git.setCommitsDelay(.milliseconds(80))
        let store = await makeCommitReadyStore(git)

        let task = Task { await store.commit(repoPath) }
        try? await Task.sleep(for: .milliseconds(15))
        // Diğer iki koşulu tek tek geri kur ki yalnız isCommitting kalsın.
        store.setCommitMessage("feat: second", for: repoPath)

        XCTAssertTrue(store.isCommitting)
        XCTAssertFalse(store.canCommit(repoPath), "uçuştaki commit ikinciyi engeller")

        await task.value
        XCTAssertTrue(store.canCommit(repoPath), "commit bitince kapı yeniden açılır")
    }

    func testCanCommitIsPerRepo() async {
        let git = FakeGitService()
        let store = await makeCommitReadyStore(git)

        XCTAssertFalse(store.canCommit("/tmp/other-repo"), "başka repo'nun taslağı sızmaz")
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

    // MARK: - Graph history (karar 40)

    private func historyCommit(
        _ hash: String,
        parents: [String] = [],
        refs: [GitRef] = []
    ) -> GitCommit {
        GitCommit(
            hash: hash,
            shortHash: String(hash.prefix(7)),
            message: "m-\(hash)",
            author: "a",
            date: Date(timeIntervalSince1970: 0),
            parentHashes: parents,
            references: refs
        )
    }

    func testLoadAllLoadsHistoryWithFixedLimit() async {
        let git = FakeGitService()
        await git.setHistory([historyCommit("aaa", parents: ["bbb"]), historyCommit("bbb")])
        let store = makeStore(git)

        await store.loadAll(repoPath)

        XCTAssertEqual(store.history[repoPath]?.map(\.hash), ["aaa", "bbb"])
        let calls = await git.historyCalls
        XCTAssertEqual(calls, [GitStore.historyLimit])
    }

    func testHeadHashComesFromCurrentRefDecoration() async {
        let git = FakeGitService()
        await git.setHistory([
            historyCommit("aaa", parents: ["bbb"]),
            historyCommit("bbb", refs: [GitRef(name: "main", kind: .localBranch, isCurrent: true)]),
        ])
        let store = makeStore(git)

        await store.loadHistory(repoPath)

        XCTAssertEqual(store.headHash[repoPath], "bbb")
    }

    func testHeadHashFallsBackToNewestCommitWithoutDecoration() async {
        let git = FakeGitService()
        await git.setHistory([historyCommit("aaa"), historyCommit("bbb")])
        let store = makeStore(git)

        await store.loadHistory(repoPath)

        XCTAssertEqual(store.headHash[repoPath], "aaa")
    }

    func testCommitURLIsBuiltOnlyForGitHubRemotes() async {
        let git = FakeGitService()
        await git.setRemoteURL("git@github.com:owner/repo.git")
        let store = makeStore(git)
        await store.loadHistory(repoPath)

        XCTAssertEqual(
            store.commitURL(repoPath, sha: "abc")?.absoluteString,
            "https://github.com/owner/repo/commit/abc"
        )
        XCTAssertTrue(store.isGitHubRepo(repoPath))

        await git.setRemoteURL("git@gitlab.com:owner/repo.git")
        await store.loadHistory(repoPath)

        XCTAssertNil(store.commitURL(repoPath, sha: "abc"))
        XCTAssertFalse(store.isGitHubRepo(repoPath))
    }

    func testPullRequestBranchRequiresGitHubRemoteAndNonDefaultBranch() async {
        let git = FakeGitService()
        await git.setRemoteURL("https://github.com/owner/repo.git")
        await git.setBranches([GitBranch(name: "feature/x", isCurrent: true)])
        let store = makeStore(git)

        await store.loadAll(repoPath)
        XCTAssertEqual(store.pullRequestBranch(repoPath), "feature/x")

        await git.setBranches([GitBranch(name: "main", isCurrent: true)])
        await store.loadAll(repoPath)
        XCTAssertNil(store.pullRequestBranch(repoPath), "default branch'te PR açılmaz")
    }

    func testGitHubCLIIsProbedOnlyOnce() async {
        let git = FakeGitService()
        await git.setGitHubCLIInstalled(true)
        let store = makeStore(git)

        await store.loadHistory(repoPath)
        await store.loadHistory(repoPath)

        XCTAssertTrue(store.isGitHubCLIAvailable)
        await git.setGitHubCLIInstalled(false)
        await store.loadHistory(repoPath)
        XCTAssertTrue(store.isGitHubCLIAvailable, "yoklama tekrarlanmamalı")
    }

    func testEvictClearsHistoryCaches() async {
        let git = FakeGitService()
        await git.setHistory([historyCommit("aaa")])
        await git.setRemoteURL("git@github.com:owner/repo.git")
        let store = makeStore(git)
        await store.loadAll(repoPath)

        store.evict(repoPath)

        XCTAssertNil(store.history[repoPath])
        XCTAssertNil(store.headHash[repoPath])
        XCTAssertNil(store.commitURL(repoPath, sha: "abc"))
    }
}
