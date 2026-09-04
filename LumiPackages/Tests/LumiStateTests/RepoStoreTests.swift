import Foundation
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiState

/// `RepoStore` karakterizasyonu (refactor plan 2.5 — bugüne dek 0 test).
/// Kilitlenen davranışlar: kaynak-bazlı gruplama sırası ve boş-root
/// görünürlüğü, file-tree ilk yükleme auto-expand'i, toggle, reload ve
/// event tüketiminin start/stop simetrisi.
@MainActor
final class RepoStoreTests: XCTestCase {
    private var service: FakeRepoService!
    private var store: RepoStore!

    override func setUp() async throws {
        service = FakeRepoService()
        store = RepoStore(service: service)
    }

    override func tearDown() async throws {
        store.stop()
    }

    private func waitUntil(
        _ description: String,
        _ condition: @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(2)
        while await !condition() {
            if Date() > deadline { return XCTFail("koşul sağlanmadı: \(description)") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - Gruplama (groupReposBySource paritesi)

    private static let rootRepo = Repo(
        name: "alpha", path: "/projects/alpha", isGitRepo: true, source: .projectsRoot
    )
    private static let extraRepo = Repo(
        name: "beta", path: "/extra/beta", isGitRepo: true,
        source: .additionalRoot(path: "/extra", label: "Extra")
    )
    private static let standaloneRepo = Repo(
        name: "solo", path: "/somewhere/solo", isGitRepo: true, source: .standalone
    )

    func testGroupOrderIsProjectsRootThenAdditionalRootsThenStandalone() async {
        await service.setRepos([Self.standaloneRepo, Self.extraRepo, Self.rootRepo])
        store.additionalPaths = [
            AdditionalPath(id: "a1", path: "/extra", type: .root, label: "Extra")
        ]
        await store.reload()

        XCTAssertEqual(
            store.groupedRepos.map(\.id),
            ["__projects_root__", "a1", "__standalone__"]
        )
        XCTAssertEqual(store.groupedRepos.map(\.label), ["Projects Root", "Extra", "Standalone Repos"])
        XCTAssertEqual(store.groupedRepos[1].repos, [Self.extraRepo])
    }

    func testAdditionalRootsFollowConfigOrderNotRepoOrder() async {
        let second = Repo(
            name: "gamma", path: "/second/gamma", isGitRepo: true,
            source: .additionalRoot(path: "/second", label: nil)
        )
        await service.setRepos([second, Self.extraRepo])
        store.additionalPaths = [
            AdditionalPath(id: "a1", path: "/extra", type: .root, label: "Extra"),
            AdditionalPath(id: "a2", path: "/second", type: .root),
        ]
        await store.reload()

        XCTAssertEqual(store.groupedRepos.map(\.id), ["a1", "a2"])
    }

    func testEmptyAdditionalRootStaysVisibleButEmptyBuiltInGroupsDisappear() async {
        // Boş root grubu KALIR (kullanıcı oraya repo koyabilsin diye görünür),
        // boş "Projects Root" / "Standalone Repos" grupları görünmez.
        await service.setRepos([])
        store.additionalPaths = [
            AdditionalPath(id: "a1", path: "/extra", type: .root, label: "Extra")
        ]
        await store.reload()

        XCTAssertEqual(store.groupedRepos.map(\.id), ["a1"])
        XCTAssertTrue(store.groupedRepos[0].repos.isEmpty)
    }

    func testRepoTypeAdditionalPathGetsNoGroupOfItsOwn() async {
        await service.setRepos([Self.standaloneRepo])
        store.additionalPaths = [AdditionalPath(id: "a1", path: "/somewhere/solo", type: .repo)]
        await store.reload()

        XCTAssertEqual(store.groupedRepos.map(\.id), ["__standalone__"], "repo tipi Standalone'a düşer")
    }

    func testAdditionalRootLabelFallsBackToLastPathComponent() async {
        await service.setRepos([])
        store.additionalPaths = [AdditionalPath(id: "a1", path: "/Users/dev/wkspaces/Github", type: .root)]
        await store.reload()

        XCTAssertEqual(store.groupedRepos.map(\.label), ["Github"])
    }

    func testRepoLookupByPath() async {
        await service.setRepos([Self.rootRepo, Self.standaloneRepo])
        await store.reload()

        XCTAssertEqual(store.repo(at: "/projects/alpha"), Self.rootRepo)
        XCTAssertNil(store.repo(at: "/nope"))
    }

    // MARK: - File tree

    private static let tree: [FileTreeNode] = [
        FileTreeNode(name: "Sources", path: "Sources", type: .folder, isIgnored: false, children: [
            FileTreeNode(name: "main.swift", path: "Sources/main.swift", type: .file, isIgnored: false),
        ]),
        FileTreeNode(name: ".build", path: ".build", type: .folder, isIgnored: true),
        FileTreeNode(name: "README.md", path: "README.md", type: .file, isIgnored: false),
    ]

    func testFirstLoadAutoExpandsRootFoldersOnly() async {
        await service.setFileTree(Self.tree, for: "/r")
        await store.loadFileTree("/r")

        XCTAssertEqual(store.fileTrees["/r"], Self.tree)
        XCTAssertEqual(
            store.expandedNodes["/r"], ["Sources"],
            "yalnız ignored OLMAYAN kök klasörler; dosyalar ve ignored klasör hariç"
        )
    }

    func testSecondLoadDoesNotReExpandCollapsedFolders() async {
        await service.setFileTree(Self.tree, for: "/r")
        await store.loadFileTree("/r")
        store.toggleNode("/r", path: "Sources") // kullanıcı kapattı

        await store.loadFileTree("/r")
        XCTAssertEqual(store.expandedNodes["/r"], [], "auto-expand repo başına tek atımlı")
    }

    func testAutoExpandIsTrackedPerRepo() async {
        await service.setFileTree(Self.tree, for: "/r1")
        await service.setFileTree(Self.tree, for: "/r2")
        await store.loadFileTree("/r1")
        store.toggleNode("/r1", path: "Sources")

        await store.loadFileTree("/r2")
        XCTAssertEqual(store.expandedNodes["/r2"], ["Sources"])
        XCTAssertEqual(store.expandedNodes["/r1"], [])
    }

    func testToggleNodeIsSymmetricAndPerRepo() async {
        store.toggleNode("/r", path: "a/b")
        XCTAssertEqual(store.expandedNodes["/r"], ["a/b"])
        store.toggleNode("/r", path: "a/b")
        XCTAssertEqual(store.expandedNodes["/r"], [])
        store.toggleNode("/other", path: "a/b")
        XCTAssertEqual(store.expandedNodes["/r"], [])
        XCTAssertEqual(store.expandedNodes["/other"], ["a/b"])
    }

    func testLoadFileTreeIsStaleWhileRevalidate() async {
        await service.setFileTree(Self.tree, for: "/r")
        await store.loadFileTree("/r")

        let replacement = [FileTreeNode(name: "new.txt", path: "new.txt", type: .file, isIgnored: false)]
        await service.setFileTree(replacement, for: "/r")
        await store.loadFileTree("/r")

        XCTAssertEqual(store.fileTrees["/r"], replacement)
        let calls = await service.fileTreeCalls
        XCTAssertEqual(calls, ["/r", "/r"])
    }

    // MARK: - start/stop event tüketimi

    func testStartLoadsOnceAndConsumesReposChanged() async throws {
        await service.setRepos([Self.rootRepo])
        store.start()
        try await waitUntil("ilk yükleme") { self.store.repos == [Self.rootRepo] }

        await service.setRepos([Self.rootRepo, Self.standaloneRepo])
        service.emit(.reposChanged)
        try await waitUntil("event sonrası tam yeniden çekme") { self.store.repos.count == 2 }
    }

    func testStartIsIdempotent() async throws {
        store.start()
        store.start()
        try await waitUntil("abonelik kuruldu") { await self.service.subscriberCount >= 1 }
        // Kısa bir pencere daha bekle: ikinci start yeni bir abonelik açsaydı görünürdü.
        try await Task.sleep(for: .milliseconds(50))
        let count = await service.subscriberCount
        XCTAssertEqual(count, 1, "ikinci start yeni tüketici açmamalı")
    }

    func testFileTreeChangedEventIsNotConsumedByStore() async throws {
        // Sözleşme: fileTreeChanged AppContainer köprüsünün işi; store yalnız
        // reposChanged'e tepki verir.
        await service.setRepos([Self.rootRepo])
        store.start()
        try await waitUntil("ilk yükleme") { self.store.repos.count == 1 }

        await service.setRepos([])
        service.emit(.fileTreeChanged(repoPath: "/r"))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(store.repos, [Self.rootRepo], "fileTreeChanged repo listesini tazelemez")
    }

    func testEventAfterStopDoesNotChangeState() async throws {
        await service.setRepos([Self.rootRepo])
        store.start()
        try await waitUntil("ilk yükleme") { self.store.repos.count == 1 }

        store.stop()
        await service.setRepos([Self.rootRepo, Self.standaloneRepo])
        service.emit(.reposChanged)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(store.repos, [Self.rootRepo], "stop sonrası event state'i değiştirmez")
    }

    func testStopThenStartResumesConsumption() async throws {
        store.start()
        try await waitUntil("abonelik") { await self.service.subscriberCount >= 1 }
        store.stop()

        await service.setRepos([Self.standaloneRepo])
        store.start()
        try await waitUntil("yeniden tüketim") { self.store.repos == [Self.standaloneRepo] }
    }
}
