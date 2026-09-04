import Foundation
import LumiKit

/// `RepoServicing` fake'i: repo listesi / dosya ağacı ayarlanabilir, watch
/// çağrıları kaydedilir (aktif repo değişiminde unwatch→watch sözleşmesi).
public actor FakeRepoService: RepoServicing {
    public struct RootsCall: Equatable, Sendable {
        public let projectsRoot: String
        public let additionalPaths: [AdditionalPath]

        public init(projectsRoot: String, additionalPaths: [AdditionalPath]) {
            self.projectsRoot = projectsRoot
            self.additionalPaths = additionalPaths
        }
    }

    private let broadcaster = EventBroadcaster<RepoEvent>()
    private let subscriptions = SubscriptionCounter()

    // MARK: Ayarlanabilir dönüşler
    private var reposToReturn: [Repo] = []
    private var fileTrees: [String: [FileTreeNode]] = [:]
    private var defaultFileTree: [FileTreeNode] = []

    // MARK: Çağrı kaydı
    public private(set) var reposCallCount = 0
    public private(set) var setRootsCalls: [RootsCall] = []
    public private(set) var fileTreeCalls: [String] = []
    public private(set) var watchCalls: [String] = []
    public private(set) var unwatchCalls: [String] = []

    public init() {}

    public func setRepos(_ repos: [Repo]) {
        reposToReturn = repos
    }

    public func setFileTree(_ nodes: [FileTreeNode], for repoPath: String) {
        fileTrees[repoPath] = nodes
    }

    public func setDefaultFileTree(_ nodes: [FileTreeNode]) {
        defaultFileTree = nodes
    }

    /// Store'lara repo event'i sürer (ör. `.fileTreeChanged`).
    public nonisolated func emit(_ event: RepoEvent) {
        broadcaster.send(event)
    }

    public func repos() async -> [Repo] {
        reposCallCount += 1
        return reposToReturn
    }

    public func setRoots(projectsRoot: String, additionalPaths: [AdditionalPath]) async {
        setRootsCalls.append(
            RootsCall(projectsRoot: projectsRoot, additionalPaths: additionalPaths)
        )
    }

    public func fileTree(repoPath: String) async -> [FileTreeNode] {
        fileTreeCalls.append(repoPath)
        return fileTrees[repoPath] ?? defaultFileTree
    }

    public func watchFileTree(repoPath: String) async {
        watchCalls.append(repoPath)
    }

    public func unwatchFileTree(repoPath: String) async {
        unwatchCalls.append(repoPath)
    }

    /// Bir tüketici `events()` çağırana kadar `emit` edilen event'ler düşer.
    public nonisolated var subscriberCount: Int { subscriptions.value }

    public nonisolated func events() -> AsyncStream<RepoEvent> {
        let stream = broadcaster.stream()
        subscriptions.increment()
        return stream
    }
}
