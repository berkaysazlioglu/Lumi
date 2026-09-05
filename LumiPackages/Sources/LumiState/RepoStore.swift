import Foundation
import LumiKit
import Observation

/// Repo listesi + kaynak bazlı gruplama.
/// Event → tam yeniden çekme (pull-after-push korunur).
@Observable
@MainActor
public final class RepoStore: StoreLifecycle {
    public private(set) var repos: [Repo] = []
    /// Gruplamanın "boş root grupları da göster" kuralı için config sırasıyla
    /// tutulur. Kapsülleme (refactor 5.4): iki yazar vardı (assembly bootstrap +
    /// `configDidChange`); ikisi de artık `setAdditionalPaths(_:)` çağırır.
    public private(set) var additionalPaths: [AdditionalPath] = []

    // File tree (file tree UI davranışları): repo başına cache (stale-while-
    /// revalidate), expand state (oturum içi), ilk-yüklemede kök klasör expand'i.
    public private(set) var fileTrees: [String: [FileTreeNode]] = [:]
    public private(set) var fileTreeRevisions: [String: Int] = [:]
    public private(set) var capabilities: [String: ProjectCapabilities] = [:]
    public private(set) var explorerOptions: [String: ExplorerOptions] = [:]
    public private(set) var explorerTrees: [String: [FileTreeNode]] = [:]
    public private(set) var expandedNodes = KeyedToggleSet<String, String>()
    @ObservationIgnored private var autoExpandedRepos: Set<String> = []

    @ObservationIgnored private let service: any RepoServicing
    @ObservationIgnored private let consumer = EventConsumer()

    public init(service: any RepoServicing) {
        self.service = service
    }

    public func start() {
        // Stream Task'tan ÖNCE alınır: `events()` nonisolated olduğundan abonelik
        // start() dönmeden kurulur, boot penceresinde event kaybolmaz (plan 5.6).
        consumer.start(
            service.events(),
            prologue: { [weak self] in await self?.reload() }
        ) { [weak self] event in
            // Yalnız repo listesi event'i; fileTreeChanged repo assembly'sinin işi
            guard event == .reposChanged else { return }
            await self?.reload()
        }
    }

    public func stop() {
        consumer.stop()
    }

    public func reload() async {
        repos = await service.repos()
    }

    /// Config aynası (bootstrap + `configDidChange`).
    public func setAdditionalPaths(_ paths: [AdditionalPath]) {
        additionalPaths = paths
    }

    public func repo(at path: String) -> Repo? {
        repos.first { $0.path == path }
    }

    // MARK: - File tree

    /// Stale-while-revalidate: eski ağaç ekranda kalır, yenisi gelince değişir.
    public func loadFileTree(_ repoPath: String) async {
        let tree = await service.fileTree(repoPath: repoPath)
        let projectCapabilities = await service.capabilities(repoPath: repoPath)
        capabilities[repoPath] = projectCapabilities
        // Unity projesi ilk açılışta otomatik Assets görünümüne geçer; kullanıcı
        // seçeneği elle değiştirdiyse (`explorerOptions` dolu) dokunulmaz.
        if projectCapabilities.isUnityProject, explorerOptions[repoPath] == nil {
            explorerOptions[repoPath] = ExplorerOptions.unityDefault
        }
        fileTrees[repoPath] = tree
        rebuildExplorer(repoPath)
        fileTreeRevisions[repoPath, default: 0] += 1
        if !autoExpandedRepos.contains(repoPath) {
            autoExpandedRepos.insert(repoPath)
            // İlk yüklemede kök seviyesindeki klasörler otomatik expand
            let rootFolders = tree.filter { $0.type == .folder && !$0.isIgnored }.map(\.path)
            expandedNodes.formUnion(rootFolders, in: repoPath)
        }
    }

    public func setExplorerOptions(_ options: ExplorerOptions, for repoPath: String) {
        var value = options
        if capabilities[repoPath]?.isUnityProject != true { value.unityAssetsOnly = false }
        explorerOptions[repoPath] = value
        rebuildExplorer(repoPath)
    }

    private func rebuildExplorer(_ repoPath: String) {
        if capabilities[repoPath]?.isUnityProject != true, explorerOptions[repoPath]?.unityAssetsOnly == true {
            explorerOptions[repoPath]?.unityAssetsOnly = false
        }
        explorerTrees[repoPath] = (explorerOptions[repoPath] ?? ExplorerOptions()).project(
            fileTrees[repoPath] ?? [], isUnityProject: capabilities[repoPath]?.isUnityProject == true
        )
    }

    public func searchContents(_ query: ExplorerContentQuery, in repoPath: String) async throws -> ExplorerContentResult {
        func paths(_ nodes: [FileTreeNode]) -> [String] {
            nodes.flatMap { $0.type == .file ? [$0.path] : paths($0.children) }
        }
        return try await service.searchContents(
            repoPath: repoPath, paths: paths(explorerTrees[repoPath] ?? []), query: query
        )
    }

    public func editFile(_ edit: ExplorerFileEdit, in repoPath: String) async throws {
        try await service.editFile(repoPath: repoPath, edit: edit)
        await loadFileTree(repoPath)
    }

    public func collapseAll(_ repoPath: String) {
        expandedNodes.replace([], in: repoPath)
    }

    public func toggleNode(_ repoPath: String, path: String) {
        expandedNodes.toggle(path, in: repoPath)
    }

    /// Tab kapanınca dosya ağacı cache'i + expand durumu boşaltılır
    /// (refactor 5.5). Yeniden açılışta ağaç servisten taze çekilir ve kök
    /// klasör auto-expand'i yeniden koşar.
    public func evict(_ repoPath: String) {
        fileTrees.removeValue(forKey: repoPath)
        capabilities.removeValue(forKey: repoPath)
        fileTreeRevisions.removeValue(forKey: repoPath)
        explorerTrees.removeValue(forKey: repoPath)
        explorerOptions.removeValue(forKey: repoPath)
        expandedNodes.evict(repoPath)
        autoExpandedRepos.remove(repoPath)
    }

    // MARK: - Gruplama (groupReposBySource paritesi)

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

    // MARK: - Seçici sorguları (refactor 7.5: RepoSelectorView'dan taşındı)

    /// Açık tab'ları gizler + isimde case-insensitive substring filtresi;
    /// grup yapısı KORUNUR (boş grup düşmez — gruplu görünümde "No repositories
    /// found" mesajı çıkar). Saf: girdiden başka bir şeye bakmaz.
    public static func filteredGroups(
        _ groups: [RepoGroup],
        excluding openTabPaths: Set<String>,
        matching query: String
    ) -> [RepoGroup] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return groups.map { group in
            RepoGroup(
                id: group.id,
                label: group.label,
                repos: group.repos.filter { repo in
                    guard !openTabPaths.contains(repo.path) else { return false }
                    return needle.isEmpty || repo.name.lowercased().contains(needle)
                }
            )
        }
    }

    /// Klavye navigasyonunun gezdiği düz liste — collapsed gruplar atlanır.
    public static func flatRepos(_ groups: [RepoGroup], collapsed: Set<String>) -> [Repo] {
        groups.flatMap { collapsed.contains($0.id) ? [] : $0.repos }
    }

    /// Store'un kendi grupları üzerinden kısayol (çağıran grupları taşımaz).
    public func filteredGroups(
        matching query: String,
        excluding openTabPaths: Set<String>
    ) -> [RepoGroup] {
        Self.filteredGroups(groupedRepos, excluding: openTabPaths, matching: query)
    }
}
