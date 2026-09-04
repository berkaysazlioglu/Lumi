import XCTest
import LumiKit
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
}
