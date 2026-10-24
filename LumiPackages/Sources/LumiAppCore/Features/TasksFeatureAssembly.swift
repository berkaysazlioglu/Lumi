import Foundation
import LumiKit
import LumiServices
import LumiState
import LumiUI
import SwiftUI

/// Sol panelin Tasks/Remote öğesi (karar 55) ve Tasks route'unun içeriği
/// (Tasks planı, Faz 1).
///
/// `TasksStore` yalnız bu feature'ındır: route view'ı ve iki sheet onu
/// descriptor closure'larından alır — `ShellContext`'e girmez. Tazeleme
/// döngüsü route view'ının ömrüne bağlı olduğu için `start` iş yapmaz.
@MainActor
final class TasksFeatureAssembly: FeatureAssembly, ShellContributing {
    let bootstrapPhase = BootstrapPhase.ui

    /// `build`'den önce nil — kabuk kaydı testlerde `build` olmadan da kurulur,
    /// bu yüzden descriptor'lar store'u çağrı anında ve zayıf okur.
    private(set) var tasks: TasksStore?
    /// Task'e özel workspace'i (karar 137) repo feature'ının store'u açar.
    private let repo: RepoFeatureAssembly

    init(repo: RepoFeatureAssembly) {
        self.repo = repo
    }

    func build(services: any ServiceRegistry, shared: SharedStores) {
        let git = services.git
        let runner = LiveTaskAgentRunner(
            terminals: shared.terminals,
            tools: services.taskAgentTools,
            createWorkspace: { [repo] projectPath, branch in
                guard let project = repo.repoStore.repo(at: projectPath) else {
                    throw TaskAgentStartError.projectNotFound(projectPath)
                }
                return try await repo.workspaceStore.createWorkspace(
                    project: project, name: TaskAgentStartError.workspaceName(for: branch), branch: branch
                ).path
            },
            trust: { ClaudeWorkspaceTrust().markTrusted(repoPath: $0) }
        )
        tasks = TasksStore(
            factory: services.taskProviders,
            config: services.config,
            credentials: services.taskCredentials,
            images: services.taskImages,
            agents: runner,
            remoteURL: { await git.remoteURL(repoPath: $0) },
            toasts: shared.toasts
        )
    }

    func registerShellItems(into registries: ShellRegistries) {
        registries.panels.register(PanelItemDescriptor(
            id: .tasks,
            title: "Tasks",
            icon: "checklist",
            defaultSlot: .left,
            sizing: .fit,
            makeView: { AnyView(TasksPanelItem()) }
        ))
        // Her bölüm orta alanın bir route'u + o route'un toolbar öğesidir.
        for section in TasksPanelSection.allCases {
            registries.routes.register(ContentRouteDescriptor(
                id: section.routeID,
                title: section.title,
                icon: section.icon,
                makeView: { [weak self] _ in
                    guard section == .tasks, let store = self?.tasks else {
                        return AnyView(TasksRouteView(section: section))
                    }
                    return AnyView(TasksScreen(store: store))
                }
            ))
            registries.toolbar.register(ToolbarItemDescriptor(
                id: ToolbarItemID("route.\(section.rawValue)"),
                region: .center,
                order: ShellToolbarItems.Order.routeTitle,
                isVisible: { $0.navigation.activeRoute == .content(section.routeID) },
                makeView: { AnyView(TasksRouteToolbarItem(section: section)) }
            ))
        }
        registerSheet(.taskConnect, into: registries, isPresented: { $0.connectFlow != nil }) {
            AnyView(TaskConnectOverlay(store: $0))
        }
        registerSheet(.newTask, into: registries, isPresented: { $0.newTaskForm != nil }) {
            AnyView(NewTaskOverlay(store: $0))
        }
        registerSheet(.startTask, into: registries, isPresented: { $0.startingTask != nil }) {
            AnyView(StartTaskOverlay(store: $0))
        }
        registerSheet(.taskFailureLog, into: registries, isPresented: { $0.isFailureLogPresented }) {
            AnyView(TaskFailureLogOverlay(store: $0))
        }
    }

    private func registerSheet(
        _ id: OverlayID,
        into registries: ShellRegistries,
        isPresented: @escaping @MainActor (TasksStore) -> Bool,
        makeView: @escaping @MainActor (TasksStore) -> AnyView
    ) {
        registries.overlays.register(OverlayDescriptor(
            id: id,
            isPresented: { [weak self] _ in self?.tasks.map(isPresented) ?? false },
            makeView: { [weak self] in
                guard let store = self?.tasks else { return AnyView(EmptyView()) }
                return makeView(store)
            }
        ))
    }

    /// Kayıtlı kaynakları ve token'larını okur; ağ isteği route açılınca.
    func start() async {
        await tasks?.load()
    }

    /// Kapanışta bekleyen birleşik yazımlar kaybolmasın.
    func shutdown() async {
        await tasks?.flushAll()
    }
}

/// Task ajanını başlatırken workspace tarafındaki hatalar.
enum TaskAgentStartError: LocalizedError {
    case projectNotFound(String)

    var errorDescription: String? {
        switch self {
        case .projectNotFound(let path): "\((path as NSString).lastPathComponent) is no longer in Projects."
        }
    }

    /// Workspace klasör adı: dal adının `task/` öneki atılmış hâli.
    static func workspaceName(for branch: String) -> String {
        branch.hasPrefix("task/") ? String(branch.dropFirst("task/".count)) : branch
    }
}
