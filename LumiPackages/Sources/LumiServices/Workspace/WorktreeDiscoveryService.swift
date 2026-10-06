import Foundation
import LumiKit

/// Karar 115: Git worktree'lerinin canlı keşfi ve izlenmesi (Orca paritesi).
///
/// Orca'dan farkı: liste 2 sn'lik yoklamayla değil kqueue dizin izleyicileriyle
/// (`DirectoryWatcher`) tazelenir; uygulama öne gelince tüketici ayrıca tam
/// tarama ister. Git hatası boş liste değil fırlatılan hatadır.
public actor WorktreeDiscoveryService: WorktreeDiscovering {
    /// Orca `WATCH_DEBOUNCE_MS = 250` paritesi.
    public static let watchDebounce: TimeInterval = 0.25
    public static let listTimeout: TimeInterval = 10
    static let git = "/usr/bin/git"

    private let runner: any ProcessRunning
    private let managedRoot: String
    private let debounce: TimeInterval
    private let broadcaster = EventBroadcaster<Void>(label: "worktrees")
    private let watchQueue = DispatchQueue(label: "lumi.worktrees.watch", qos: .utility)
    private var watchers: [String: DirectoryWatcher] = [:]
    /// Ortak git dizini değişmez; yalnız başarılı sorgular saklanır.
    private var commonDirectories: [String: String] = [:]

    public init(
        runner: any ProcessRunning = SystemProcessRunner(),
        managedRoot: URL = WorkspaceService.defaultRoot,
        debounce: TimeInterval = WorktreeDiscoveryService.watchDebounce
    ) {
        self.runner = runner
        self.managedRoot = CanonicalPath.of(managedRoot.path)
        self.debounce = debounce
    }

    public func worktrees(projectPath: String) async throws -> [GitWorktreeEntry] {
        let project = CanonicalPath.of(projectPath)
        guard Self.isDirectory(project) else {
            throw WorkspaceFailure("Project folder is unavailable: \(project)")
        }
        var nulSeparated = true
        var output = await list(at: project, arguments: ["-z"])
        if output?.exitCode != 0 {
            // Git < 2.36 `-z`'yi tanımaz; satır biçimine düşülür.
            nulSeparated = false
            output = await list(at: project, arguments: [])
        }
        guard let output, output.exitCode == 0 else {
            let detail = output?.stderr.trimmingCharacters(in: .whitespacesAndNewlines) ?? "timed out"
            throw WorkspaceFailure("git worktree list failed in \(project): \(detail)")
        }
        let raw = GitWorktreeListParser.parse(output.stdout, nulSeparated: nulSeparated)
        return raw.enumerated().map { index, entry in makeEntry(entry, isMain: index == 0) }
    }

    public func watch(projectPaths: [String], checkoutPaths: [String]) async {
        var desired = Set<String>()
        for project in projectPaths {
            guard let common = await commonDirectory(of: CanonicalPath.of(project)) else { continue }
            let worktrees = (common as NSString).appendingPathComponent("worktrees")
            desired.insert(Self.isDirectory(worktrees) ? worktrees : common)
        }
        for checkout in checkoutPaths {
            let parent = (CanonicalPath.of(checkout) as NSString).deletingLastPathComponent
            if Self.isDirectory(parent) { desired.insert(parent) }
        }
        for (path, watcher) in watchers where !desired.contains(path) {
            watcher.cancel()
            watchers.removeValue(forKey: path)
        }
        for path in desired where watchers[path] == nil {
            watchers[path] = DirectoryWatcher(path: path, queue: watchQueue, debounce: debounce) { [broadcaster] in
                broadcaster.send(())
            }
        }
    }

    public nonisolated func changes() -> AsyncStream<Void> {
        broadcaster.stream()
    }

    // MARK: - Yardımcılar

    private func list(at project: String, arguments: [String]) async -> ProcessOutput? {
        await runner.run(
            Self.git, arguments: ["worktree", "list", "--porcelain"] + arguments,
            currentDirectory: project, timeout: Self.listTimeout
        )
    }

    private func makeEntry(_ raw: GitWorktreeListParser.RawEntry, isMain: Bool) -> GitWorktreeEntry {
        let path = CanonicalPath.of(raw.path)
        // Git < 2.31 `prunable` yazmaz; klasörün yokluğu aynı anlama gelir.
        // Kilitli worktree çıkarılabilir bir diskte olabilir, düşürülmez.
        let isGone = !isMain && !raw.isBare && !raw.isLocked && !Self.entryExists(path)
        return GitWorktreeEntry(
            path: path, branch: raw.branch, isMain: isMain, isBare: raw.isBare,
            isLocked: raw.isLocked, isPrunable: raw.isPrunable || isGone,
            isInsideManagedRoot: path != managedRoot && CanonicalPath.contains(path, in: managedRoot)
        )
    }

    private func commonDirectory(of project: String) async -> String? {
        if let cached = commonDirectories[project] { return cached }
        guard let output = await runner.run(
            Self.git, arguments: ["rev-parse", "--git-common-dir"],
            currentDirectory: project, timeout: Self.listTimeout
        ), output.exitCode == 0 else { return nil }
        let reported = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reported.isEmpty else { return nil }
        // Ana checkout'ta göreli (`.git`) döner.
        let absolute = reported.hasPrefix("/") ? reported : (project as NSString).appendingPathComponent(reported)
        let common = CanonicalPath.of(absolute)
        commonDirectories[project] = common
        return common
    }

    private static func entryExists(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path)) != nil
    }

    private static func isDirectory(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
    }
}
