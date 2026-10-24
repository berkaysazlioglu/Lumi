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
        tasks = TasksStore(factory: services.taskProviders, toasts: shared.toasts)
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
        registries.overlays.register(OverlayDescriptor(
            id: .taskConnect,
            isPresented: { [weak self] _ in self?.tasks?.connectFlow != nil },
            makeView: { [weak self] in
                guard let store = self?.tasks else { return AnyView(EmptyView()) }
                return AnyView(TaskConnectOverlay(store: store))
            }
        ))
        registries.overlays.register(OverlayDescriptor(
            id: .newTask,
            isPresented: { [weak self] _ in self?.tasks?.newTaskForm != nil },
            makeView: { [weak self] in
                guard let store = self?.tasks else { return AnyView(EmptyView()) }
                return AnyView(NewTaskOverlay(store: store))
            }
        ))
    }

    func start() async {}

    func shutdown() async {}
}
