import Foundation
import XCTest
import LumiKit
import LumiState
import LumiTestSupport
@testable import LumiAppCore

/// Refactor 5.5: tab kapanınca repo/git bellek cache'leri boşaltılır.
/// Alt store'ların `evict`'i ve `onTabClosed` event'i ayrı ayrı test edilmiş;
/// bu test composition'daki BAĞLAMAYI (`wireTabClosed`) doğrular.
@MainActor
final class RepoFeatureAssemblyEvictionTests: XCTestCase {
    private var registry: FakeServiceRegistry!
    private var shared: SharedStores!

    override func setUp() async throws {
        registry = FakeServiceRegistry()
        shared = SharedStores.make(
            config: registry.config,
            terminal: registry.terminal,
            toastAutoDismissAfter: 60
        )
    }

    override func tearDown() async throws {
        registry.removeTemporaryDirectories()
        registry = nil
        shared = nil
    }

    func testClosingTabEvictsRepoAndGitCaches() async {
        let repoPath = "/tmp/lumi-evict-repo"
        await registry.fakeRepo.setDefaultFileTree([
            FileTreeNode(name: "Sources", path: "Sources", type: .folder, isIgnored: false, children: []),
        ])
        let assembly = RepoFeatureAssembly()
        assembly.build(services: registry, shared: shared)
        await assembly.start()

        shared.navigation.openTab(repoPath)
        await assembly.repoStore.loadFileTree(repoPath)
        await assembly.gitStore.loadAll(repoPath)
        XCTAssertNotNil(assembly.repoStore.fileTrees[repoPath])

        shared.navigation.closeTab(repoPath)

        XCTAssertNil(assembly.repoStore.fileTrees[repoPath])
        XCTAssertNil(assembly.gitStore.changes[repoPath])
    }
}
