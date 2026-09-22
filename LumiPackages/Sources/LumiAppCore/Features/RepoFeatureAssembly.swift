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
    private(set) var quickCommands: QuickCommandStore!
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
        quickCommands = QuickCommandStore(
            config: services.config, generator: services.quickCommandGenerator,
            scripts: services.quickCommandScripts, launcher: services.quickCommandLauncher,
            toasts: shared.toasts
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
            id: .quickCommands,
            isPresented: {
                if case .quickCommands = $0.dialogs.active { return true }
                return false
            },
            makeView: { AnyView(QuickCommandsOverlay()) }
        ))
        registries.overlays.register(OverlayDescriptor(
            id: .deleteWorkspaceDialog,
            isPresented: { $0.dialogs.deleteWorkspaceDialog != nil },
            makeView: { AnyView(DeleteWorkspaceDialogOverlay()) }
        ))
        registries.overlays.register(OverlayDescriptor(
            id: .deleteAgentSessionDialog,
            isPresented: { $0.dialogs.deleteAgentSessionDialog != nil },
            makeView: { AnyView(DeleteAgentSessionDialogOverlay()) }
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
        await quickCommands.load()
        // SIRA: workspace yüklemesi repoStore.reload'dan SONRA (migration repo
        // listesini okur); tek ui-state okumasıyla önce navigation, sonra layout.
        let uiState = await services.config.uiState()
        shared.loadWorkspace(state: uiState, repos: repoStore.repos)

        wireProjectNavigation()
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
        if old.projectQuickCommands != new.projectQuickCommands {
            quickCommands.update(new.projectQuickCommands)
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

    /// Karar 84: git olmayan projede git taburu (dal + durum + özet + geçmiş +
    /// dal başına commit listesi) her dosya değişiminde boşuna koşuyordu; her
    /// komut exit 128 ile sessizce düşüyor ama süreç yine de açılıyordu.
    /// Explorer'ın yenile butonu bu kapıyı zaten kullanıyordu, izleyici yolu
    /// kullanmıyordu. Yetenek bilgisi her iki çağrı yerinde de hemen önceki
    /// `loadFileTree` içinde tazelendiği için `git init` bir sonraki dosya
    /// değişiminde kendiliğinden yakalanır.
    private func isGitRepo(_ repoPath: String) -> Bool {
        repoStore.capabilities[repoPath]?.isGitRepo == true
    }

    // MARK: - Aktif repo

    /// Aktif repo değişimi: tek repo izlenir + git/tree yüklenir.
    /// Karar 65: indeksli kısayolun ve ⌘O'nun gezdiği liste PROJELER'dir.
    /// `NavigationStore` proje store'una bağımlı olmasın diye bağlantı iki
    /// okuma closure'ıyla kurulur (bkz. `NavigationStore.projectOrder`).
    ///
    /// Checkout sırası panelle AYNI olmalı ki ileride bir "N. checkout"
    /// kısayolu eklenirse görülenle tutarlı olsun: önce projenin kendi kökü,
    /// sonra yönetilen workspace'ler.
    private func wireProjectNavigation() {
        shared.navigation.projectOrder = { [weak self] in
            self?.workspaceStore.addedProjects.map(\.path) ?? []
        }
        shared.navigation.projectCheckouts = { [weak self] projectPath in
            guard let self else { return [projectPath] }
            return [projectPath] + workspaceStore.workspaces(for: projectPath).map(\.path)
        }
    }

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
                if self.isGitRepo(current) {
                    await self.gitStore.loadAll(current)
                }
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
                if self.isGitRepo(repoPath) {
                    // Karar 84: remote adresi yapılandırmadır, her dosya
                    // yazımında yeniden sorulmaz.
                    await self.gitStore.refresh(repoPath, rescanRemote: false)
                }
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
