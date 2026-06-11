import Foundation
import LumiKit

/// Repo keşfi + kök dizin izleme (spec/12 §1, design/02 §3).
///
/// Keşif paritesi: kökler non-recursive ilk seviye taranır; `.`-prefix ve
/// dizin-olmayanlar atlanır; `<dir>/.git` (dosya VEYA dizin — submodule sayılır)
/// → isGitRepo; git olmayan dizinler de listelenir; mutlak-path dedup ilk-kazanır;
/// var olmayan path'ler sessizce atlanır. Kök watcher'ları 300ms debounce'ludur;
/// "olay → tam reload" stratejisi korunur (pull-after-push).
public actor RepoService: RepoServicing {
    public static let rootWatchDebounce: TimeInterval = 0.3

    private let broadcaster = EventBroadcaster<RepoEvent>()
    private let watchQueue = DispatchQueue(label: "lumi.repo.watch", qos: .utility)
    private let watchDebounce: TimeInterval

    private var projectsRoot = ""
    private var additionalPaths: [AdditionalPath] = []
    private var rootWatchers: [String: DirectoryWatcher] = [:]

    public init(watchDebounce: TimeInterval = RepoService.rootWatchDebounce) {
        self.watchDebounce = watchDebounce
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

    public func events() -> AsyncStream<RepoEvent> {
        broadcaster.stream()
    }

    // MARK: - Keşif

    private func scanRoot(_ root: String, source: RepoSource) -> [Repo] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else {
            return [] // var olmayan kök sessizce atlanır (spec/12)
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

    /// Yalnız baştaki `~` home'a açılır; `~user` desteklenmez (spec/12 paritesi).
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
