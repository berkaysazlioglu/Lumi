import Foundation
import LumiKit
import Observation

/// Repo listesi + kaynak bazlı gruplama (spec/21 §14-15).
/// Event → tam yeniden çekme (pull-after-push korunur).
@Observable
@MainActor
public final class RepoStore {
    public private(set) var repos: [Repo] = []
    /// Gruplamanın "boş root grupları da göster" kuralı için config sırasıyla tutulur.
    public var additionalPaths: [AdditionalPath] = []

    // File tree (spec/12 §9 UI davranışları): repo başına cache (stale-while-
    /// revalidate), expand state (oturum içi), ilk-yüklemede kök klasör expand'i.
    public private(set) var fileTrees: [String: [FileTreeNode]] = [:]
    public private(set) var expandedNodes: [String: Set<String>] = [:]
    @ObservationIgnored private var autoExpandedRepos: Set<String> = []

    @ObservationIgnored private let service: any RepoServicing
    @ObservationIgnored private var consumeTask: Task<Void, Never>?

    public init(service: any RepoServicing) {
        self.service = service
    }

    public func start() {
        guard consumeTask == nil else { return }
        consumeTask = Task { @MainActor [weak self, service] in
            let stream = await service.events()
            await self?.reload()
            for await _ in stream {
                await self?.reload()
            }
        }
    }

    public func stop() {
        consumeTask?.cancel()
        consumeTask = nil
    }

    public func reload() async {
        repos = await service.repos()
    }

    public func repo(at path: String) -> Repo? {
        repos.first { $0.path == path }
    }

    // MARK: - File tree

    /// Stale-while-revalidate: eski ağaç ekranda kalır, yenisi gelince değişir.
    public func loadFileTree(_ repoPath: String) async {
        let tree = await service.fileTree(repoPath: repoPath)
        fileTrees[repoPath] = tree
        if !autoExpandedRepos.contains(repoPath) {
            autoExpandedRepos.insert(repoPath)
            // İlk yüklemede kök seviyesindeki klasörler otomatik expand (spec/12 §9)
            let rootFolders = tree.filter { $0.type == .folder && !$0.isIgnored }.map(\.path)
            expandedNodes[repoPath, default: []].formUnion(rootFolders)
        }
    }

    public func toggleNode(_ repoPath: String, path: String) {
        var expanded = expandedNodes[repoPath] ?? []
        if expanded.contains(path) {
            expanded.remove(path)
        } else {
            expanded.insert(path)
        }
        expandedNodes[repoPath] = expanded
    }

    public func isNodeExpanded(_ repoPath: String, path: String) -> Bool {
        expandedNodes[repoPath]?.contains(path) ?? false
    }

    // MARK: - Gruplama (spec/21 §15 — groupReposBySource paritesi)

    public struct RepoGroup: Identifiable, Equatable {
        public let id: String
        public let label: String
        public let repos: [Repo]

        public init(id: String, label: String, repos: [Repo]) {
            self.id = id
            self.label = label
            self.repos = repos
        }
    }

    /// Sıra: (1) Projects Root (boşsa görünmez), (2) root-tipi additional path'ler
    /// config sırasıyla (BOŞ olsa bile görünür; label = verilen ya da path'in son
    /// segmenti), (3) Standalone Repos (boşsa görünmez).
    public var groupedRepos: [RepoGroup] {
        var groups: [RepoGroup] = []

        let rootRepos = repos.filter { $0.source == .projectsRoot }
        if !rootRepos.isEmpty {
            groups.append(RepoGroup(id: "__projects_root__", label: "Projects Root", repos: rootRepos))
        }

        for additional in additionalPaths where additional.type == .root {
            let members = repos.filter {
                if case .additionalRoot(let path, _) = $0.source {
                    return path == additional.path
                }
                return false
            }
            let label = additional.label ?? (additional.path as NSString).lastPathComponent
            groups.append(RepoGroup(id: additional.id, label: label, repos: members))
        }

        let standalone = repos.filter { $0.source == .standalone }
        if !standalone.isEmpty {
            groups.append(RepoGroup(id: "__standalone__", label: "Standalone Repos", repos: standalone))
        }

        return groups
    }
}
