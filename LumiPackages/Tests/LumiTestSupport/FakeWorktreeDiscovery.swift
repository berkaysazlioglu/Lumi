import Foundation
import LumiKit

/// Karar 115: proje başına ayarlanabilir worktree listesi (ya da hata),
/// izleme çağrılarının kaydı ve elle tetiklenen değişim sinyali.
public actor FakeWorktreeDiscovery: WorktreeDiscovering {
    private var outcomes: [String: Result<[GitWorktreeEntry], Error>] = [:]
    private var _listCalls: [String] = []
    private var _watchCalls: [(projects: [String], checkouts: [String])] = []
    private let broadcaster = EventBroadcaster<Void>(label: "fake-worktrees")

    public init() {}

    public func setWorktrees(_ entries: [GitWorktreeEntry], for projectPath: String) {
        outcomes[projectPath] = .success(entries)
    }
    public func setFailure(_ error: Error, for projectPath: String) { outcomes[projectPath] = .failure(error) }
    public var listCalls: [String] { _listCalls }
    public var watchCalls: [(projects: [String], checkouts: [String])] { _watchCalls }
    public nonisolated func emitChange() { broadcaster.send(()) }

    public func worktrees(projectPath: String) async throws -> [GitWorktreeEntry] {
        _listCalls.append(projectPath)
        // Ayarlanmamış proje: yalnız kendisi (ana checkout).
        return try outcomes[projectPath]?.get() ?? [GitWorktreeEntry(path: projectPath, branch: "main", isMain: true)]
    }

    public func watch(projectPaths: [String], checkoutPaths: [String]) async {
        _watchCalls.append((projectPaths, checkoutPaths))
    }

    public nonisolated func changes() -> AsyncStream<Void> { broadcaster.stream() }
}
