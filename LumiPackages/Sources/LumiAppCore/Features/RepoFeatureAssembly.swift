import Foundation
import LumiKit
import LumiState
import LumiUI
import SwiftUI

/// Repo keşfi, dosya ağacı ve git verileri (refactor 3.3).
///
/// Bootstrap sırasının iki sözleşmesi buradadır ve `AppContainerBootstrapTests`
/// bunları doğrular:
/// - `repoStore.additionalPaths` **`repoStore.start()`'tan ÖNCE** yazılır,
/// - `shared.loadWorkspace(state:repos:)` **`repoStore.reload()`'dan SONRA** çağrılır
///   (ui-state migration'ı repo listesini okur).
@MainActor
final class RepoFeatureAssembly: FeatureAssembly, ShellContributing {
    let bootstrapPhase = BootstrapPhase.repo

    private(set) var repoStore: RepoStore!
    private(set) var workspaceStore: ProjectWorkspaceStore!
    private(set) var gitStore: GitStore!
    private(set) var plasticStore: PlasticStore!
    private(set) var commitAssistant: CommitMessageAssistant!
    private(set) var agentHistory: AgentHistoryStore!
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
        workspaceStore = ProjectWorkspaceStore(
            service: services.workspaces, config: services.config,
            repos: repoStore, toasts: shared.toasts
        )
        agentHistory = AgentHistoryStore(
            service: services.agentHistory, transfer: services.agentSessionTransfer, toasts: shared.toasts
        )
        gitStore = GitStore(git: services.git, toasts: shared.toasts)
        plasticStore = PlasticStore(service: services.plastic, toasts: shared.toasts)
        commitAssistant = CommitMessageAssistant(generator: services.commitMessages, toasts: shared.toasts)
        fileViewer = FileViewerStore(git: services.git, toasts: shared.toasts)
    }

    /// Faz 6.6: repo'ya bağlı panel öğeleri BU assembly'nin katkısıdır.
    func registerShellItems(into registries: ShellRegistries) {
        registries.panels.register(PanelItemDescriptor(
            id: .projects, title: "Projects", icon: "folder",
            defaultSlot: .left,
            makeView: { AnyView(ProjectsPanel()) }
        ))
        registries.overlays.register(OverlayDescriptor(
            id: .createWorkspace,
            isPresented: {
                if case .createWorkspace = $0.dialogs.active { return true }
                return false
            },
            makeView: { AnyView(CreateWorkspaceOverlay()) }
        ))
        registries.overlays.register(OverlayDescriptor(
            id: .deleteWorkspaceDialog,
            isPresented: { $0.dialogs.deleteWorkspaceDialog != nil },
            makeView: { AnyView(DeleteWorkspaceDialogOverlay()) }
        ))
        registries.panels.register(PanelItemDescriptor(
            id: .projectTools,
            title: "Project Tools",
            icon: "sidebar.right",
            defaultSlot: .right,
            isAvailable: { $0.activeRepoPath != nil },
            makeView: { AnyView(ProjectToolsPanel()) }
        ))
    }

    func start() async {
        let config = await services.config.config()
        // SIRA: additionalPaths start()'tan önce (aksi halde ilk reload eksik grup üretir)
        repoStore.setAdditionalPaths(config.additionalPaths)
        await services.repo.setRoots(
            projectsRoot: config.projectsRoot,
            additionalPaths: config.additionalPaths
        )

        repoStore.start()
        await repoStore.reload()
        await workspaceStore.load()
        // SIRA: workspace yüklemesi repoStore.reload'dan SONRA (migration repo
        // listesini okur); tek ui-state okumasıyla önce navigation, sonra layout.
        let uiState = await services.config.uiState()
        shared.loadWorkspace(state: uiState, repos: repoStore.repos)

        wireActiveRepo()
        wireTabClosed()
        startFileTreeBridge()
    }

    func configDidChange(old: AppConfig, new: AppConfig) {
        if old.sidebarProjectPaths != new.sidebarProjectPaths {
            workspaceStore.updateSidebarProjects(new.sidebarProjectPaths)
        }
        if old.workspaces != new.workspaces {
            workspaceStore.updateRecords(new.workspaces)
        }
        guard old.projectsRoot != new.projectsRoot
            || old.additionalPaths != new.additionalPaths else { return }
        repoStore.setAdditionalPaths(new.additionalPaths)
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

    private func isPlasticWorkspace(_ repoPath: String) -> Bool {
        repoStore.capabilities[repoPath]?.isPlasticWorkspace == true
    }

    // MARK: - Aktif repo

    /// Aktif repo değişimi: tek repo izlenir + git/tree yüklenir.
    private func wireActiveRepo() {
        shared.navigation.onActiveRepoChanged = { [weak self] previous, current in
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
                // Karar 46: `cm` yalnız `.plastic/` tanınan dizinde koşar.
                if self.isPlasticWorkspace(current) {
                    await self.plasticStore.loadAll(current)
                }
            }
        }
        // Bootstrap'te aktif tab varsa ilk yükleme (load() callback'ten önce kuruldu)
        if let active = shared.navigation.activeRepoPath {
            shared.navigation.onActiveRepoChanged?(nil, active)
        }
    }

    /// Tab kapanışı → repo'ya ait bellek cache'lerinin boşaltılması
    /// (refactor 5.5). `LayoutStore.projectGridLayouts` KASITLI olarak
    /// korunur: persist edilen kullanıcı tercihidir (karar 9).
    private func wireTabClosed() {
        shared.navigation.onTabClosed = { [weak self] repoPath in
            guard let self else { return }
            gitStore.evict(repoPath)
            plasticStore.evict(repoPath)
            agentHistory.evict(repoPath)
            repoStore.evict(repoPath)
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
            if self.shared.navigation.activeRepoPath == repoPath {
                await self.gitStore.refresh(repoPath)
                if self.isPlasticWorkspace(repoPath) {
                    await self.plasticStore.refreshStatus(repoPath)
                }
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
