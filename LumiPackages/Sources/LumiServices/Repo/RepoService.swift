import Foundation
import LumiKit

/// Repo keşfi + kök dizin izleme (design/02 §3).
///
/// Keşif paritesi: kökler non-recursive ilk seviye taranır; `.`-prefix ve
/// dizin-olmayanlar atlanır; `<dir>/.git` (dosya VEYA dizin — submodule sayılır)
/// → isGitRepo; git olmayan dizinler de listelenir; mutlak-path dedup ilk-kazanır;
/// var olmayan path'ler sessizce atlanır. Kök watcher'ları 300ms debounce'ludur;
/// "olay → tam reload" stratejisi korunur (pull-after-push).
public actor RepoService: RepoServicing {
    public static let rootWatchDebounce: TimeInterval = 0.3
    public static let fileTreeWatchLatency: TimeInterval = 0.5

    private let runner: any ProcessRunning
    private let broadcaster = EventBroadcaster<RepoEvent>()
    private let watchQueue = DispatchQueue(label: "lumi.repo.watch", qos: .utility)
    private let watchDebounce: TimeInterval

    private var projectsRoot = ""
    private var additionalPaths: [AdditionalPath] = []
    private var rootWatchers: [String: DirectoryWatcher] = [:]
    private var fileTreeWatchers: [String: RecursiveDirectoryWatcher] = [:]

    public init(
        watchDebounce: TimeInterval = RepoService.rootWatchDebounce,
        runner: any ProcessRunning = SystemProcessRunner()
    ) {
        self.watchDebounce = watchDebounce
        self.runner = runner
    }

    public func setRoots(projectsRoot: String, additionalPaths: [AdditionalPath]) {
        self.projectsRoot = projectsRoot
        self.additionalPaths = additionalPaths
        rebuildRootWatchers()
        broadcaster.send(.reposChanged)
    }

    public func repos() -> [Repo] {
        var seenPaths = Set<String>()
        var result: [Repo] = []

        func add(_ repo: Repo) {
            guard seenPaths.insert(repo.path).inserted else { return }
            result.append(repo)
        }

        if !projectsRoot.isEmpty {
            for repo in scanRoot(expand(projectsRoot), source: .projectsRoot) {
                add(repo)
            }
        }
        for additional in additionalPaths {
            let expanded = expand(additional.path)
            switch additional.type {
            case .root:
                let source = RepoSource.additionalRoot(path: additional.path, label: additional.label)
                for repo in scanRoot(expanded, source: source) {
                    add(repo)
                }
            case .repo:
                guard isDirectory(expanded) else { continue }
                add(Repo(
                    name: (expanded as NSString).lastPathComponent,
                    path: expanded,
                    isGitRepo: hasGitEntry(expanded),
                    source: .standalone
                ))
            }
        }
        return result
    }

    public nonisolated func events() -> AsyncStream<RepoEvent> {
        broadcaster.stream()
    }

    public func searchContents(repoPath: String, paths: [String], query: String) async throws -> ExplorerContentResult {
        try await ExplorerContentSearcher.search(repoPath: repoPath, paths: paths, query: query)
    }

    public func editFile(repoPath: String, edit: ExplorerFileEdit) async throws {
        try ExplorerFileEditor().apply(edit, repoPath: repoPath)
        broadcaster.send(.fileTreeChanged(repoPath: repoPath))
    }

    public func capabilities(repoPath: String) async -> ProjectCapabilities {
        let git = await runner.run(
            "/usr/bin/git", arguments: ["rev-parse", "--is-inside-work-tree"],
            currentDirectory: repoPath, timeout: 5
        )
        return ProjectCapabilities(
            isGitRepo: git?.exitCode == 0 && git?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true",
            isUnityProject: isDirectory(repoPath + "/Assets")
                && FileManager.default.fileExists(atPath: repoPath + "/ProjectSettings/ProjectVersion.txt")
        )
    }

    // MARK: - File tree (karar 7)

    /// Tarama actor dışında, detached bir utility task'te koşar: devasa bir
    /// kökte dakikalar sürebilen senkron iş RepoService'i (repo listesi,
    /// watcher yönetimi) kilitlemesin (karar 28).
    public func fileTree(repoPath: String) async -> [FileTreeNode] {
        let ignored = await gitIgnoredPaths(repoPath)
        return await Task.detached(priority: .utility) {
            FileTreeBuilder.build(root: repoPath, ignoredPaths: ignored)
        }.value
    }

    /// Tek git çağrısıyla ignored set'i: nested .gitignore + global excludes +
    /// .git/info/exclude dahil (karar 7'nin bilinçli sapması). Tamamen-ignored
    /// dizinler `--directory` ile trailing-slash'li tek girdiye çöker — file
    /// tree o dizine inmez. Git olmayan dizinde sessizce boş döner.
    private func gitIgnoredPaths(_ repoPath: String) async -> Set<String> {
        guard let output = await runner.run(
            "/usr/bin/git",
            arguments: ["ls-files", "--others", "--ignored", "--exclude-standard", "--directory", "-z"],
            currentDirectory: repoPath,
            timeout: 15
        ), output.exitCode == 0 else {
            return []
        }
        return Set(output.stdout.split(separator: "\0").map(String.init))
    }

    public func watchFileTree(repoPath: String) {
        guard fileTreeWatchers[repoPath] == nil else { return }
        fileTreeWatchers[repoPath] = RecursiveDirectoryWatcher(
            path: repoPath,
            latency: Self.fileTreeWatchLatency,
            queue: watchQueue,
            excludedNames: FileTreeBuilder.watchNoiseNames
        ) { [broadcaster] in
            broadcaster.send(.fileTreeChanged(repoPath: repoPath))
        }
    }

    public func unwatchFileTree(repoPath: String) {
        fileTreeWatchers.removeValue(forKey: repoPath)?.cancel()
    }

    // MARK: - Keşif

    private func scanRoot(_ root: String, source: RepoSource) -> [Repo] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else {
            return [] // var olmayan kök sessizce atlanır
        }
        return entries.sorted().compactMap { name in
            guard !name.hasPrefix(".") else { return nil }
            let fullPath = root + "/" + name
            guard isDirectory(fullPath) else { return nil }
            return Repo(
                name: name,
                path: fullPath,
                isGitRepo: hasGitEntry(fullPath),
                source: source
            )
        }
    }

    /// Yalnız baştaki `~` home'a açılır; `~user` desteklenmez (Electron paritesi).
    private func expand(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return NSHomeDirectory() + String(path.dropFirst(1))
    }

    private func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private func hasGitEntry(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path + "/.git")
    }

    // MARK: - Kök izleme

    private func rebuildRootWatchers() {
        var desired = Set<String>()
        if !projectsRoot.isEmpty {
            desired.insert(expand(projectsRoot))
        }
        for additional in additionalPaths where additional.type == .root {
            desired.insert(expand(additional.path))
        }

        for (path, watcher) in rootWatchers where !desired.contains(path) {
            watcher.cancel()
            rootWatchers.removeValue(forKey: path)
        }
        for path in desired where rootWatchers[path] == nil && isDirectory(path) {
            rootWatchers[path] = DirectoryWatcher(
                path: path,
                queue: watchQueue,
                debounce: watchDebounce
            ) { [broadcaster] in
                broadcaster.send(.reposChanged)
            }
        }
    }
}
