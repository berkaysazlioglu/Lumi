import Foundation
import LumiKit
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

    func build(services: any ServiceRegistry, shared: SharedStores) {
        tasks = TasksStore(
            factory: services.taskProviders,
            images: services.taskImages,
            agents: services.taskAgents,
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

    func start() async {}

    /// Kapanışta bekleyen birleşik yazımlar kaybolmasın.
    func shutdown() async {
        await tasks?.flushAll()
    }
}
