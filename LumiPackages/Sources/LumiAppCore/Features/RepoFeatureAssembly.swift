import Foundation
import LumiKit
import LumiState

/// Repo keşfi, dosya ağacı ve git verileri (refactor 3.3).
///
/// Bootstrap sırasının iki sözleşmesi buradadır ve `AppContainerBootstrapTests`
/// bunları doğrular:
/// - `repoStore.additionalPaths` **`repoStore.start()`'tan ÖNCE** yazılır,
/// - `workspace.load(repos:)` **`repoStore.reload()`'dan SONRA** çağrılır
///   (ui-state migration'ı repo listesini okur).
@MainActor
final class RepoFeatureAssembly: FeatureAssembly {
    let bootstrapPhase = BootstrapPhase.repo

    private(set) var repoStore: RepoStore!
    private(set) var gitStore: GitStore!
    private(set) var fileViewer: FileViewerStore!

    private var services: (any ServiceRegistry)!
    private var shared: SharedStores!
    private var fileTreeBridge: Task<Void, Never>?
    /// Kök güncellemeleri sıralı kalmalı: iki hızlı config değişimi
    /// `setRoots`'u ters sırada uygulamamalı.
    private var rootsTask: Task<Void, Never>?

    func build(services: any ServiceRegistry, shared: SharedStores) {
        self.services = services
        self.shared = shared
        repoStore = RepoStore(service: services.repo)
        gitStore = GitStore(git: services.git, toasts: shared.toasts)
        fileViewer = FileViewerStore(git: services.git, toasts: shared.toasts)
    }

    func start() async {
        let config = await services.config.config()
        // SIRA: additionalPaths start()'tan önce (aksi halde ilk reload eksik grup üretir)
        repoStore.additionalPaths = config.additionalPaths
        await services.repo.setRoots(
            projectsRoot: config.projectsRoot,
            additionalPaths: config.additionalPaths
        )

        repoStore.start()
        await repoStore.reload()
        // SIRA: workspace.load repoStore.reload'dan SONRA (migration repo listesini okur)
        await shared.workspace.load(repos: repoStore.repos)

        wireActiveRepo()
        startFileTreeBridge()
    }

    func configDidChange(old: AppConfig, new: AppConfig) {
        guard old.projectsRoot != new.projectsRoot
            || old.additionalPaths != new.additionalPaths else { return }
        repoStore.additionalPaths = new.additionalPaths
        let previous = rootsTask
        let repo = services.repo
        rootsTask = Task { @MainActor in
            await previous?.value
            await repo.setRoots(
                projectsRoot: new.projectsRoot,
                additionalPaths: new.additionalPaths
            )
        }
    }

    func shutdown() async {
        fileTreeBridge?.cancel()
        fileTreeBridge = nil
        rootsTask?.cancel()
        rootsTask = nil
        repoStore.stop()
    }

    // MARK: - Aktif repo

    /// Aktif repo değişimi: tek repo izlenir + git/tree yüklenir.
    private func wireActiveRepo() {
        shared.workspace.onActiveRepoChanged = { [weak self] previous, current in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let previous, previous != current {
                    await self.services.repo.unwatchFileTree(repoPath: previous)
                }
                guard let current else { return }
                await self.services.repo.watchFileTree(repoPath: current)
                await self.repoStore.loadFileTree(current)
                await self.gitStore.loadAll(current)
            }
        }
        // Bootstrap'te aktif tab varsa ilk yükleme (load() callback'ten önce kuruldu)
        if let active = shared.workspace.activeTab {
            shared.workspace.onActiveRepoChanged?(nil, active)
        }
    }

    /// `fileTreeChanged` → dosya ağacı tazeleme + git panellerinin canlılığı.
    /// Coalescing (karar 28): tarama uçuştayken gelen event'ler tek bir
    /// follow-up'a çöker; for-await döngüsü asla taramayı beklemez.
    private func startFileTreeBridge() {
        guard fileTreeBridge == nil else { return }
        let coalescer = KeyedRefreshCoalescer { [weak self] repoPath in
            guard let self else { return }
            await self.repoStore.loadFileTree(repoPath)
            if self.shared.workspace.activeTab == repoPath {
                await self.gitStore.refresh(repoPath)
            }
        }
        let stream = services.repo.events()
        fileTreeBridge = Task { @MainActor [weak self] in
            for await event in stream {
                guard self != nil else { return }
                if case .fileTreeChanged(let repoPath) = event {
                    coalescer.request(repoPath)
                }
            }
        }
    }
}
