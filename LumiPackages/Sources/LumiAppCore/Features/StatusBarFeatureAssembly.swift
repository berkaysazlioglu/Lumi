import Foundation
import LumiKit
import LumiState
import LumiUI
import SwiftUI

/// Alt bar segmentleri (karar 43): Keep computer awake + Resource Manager.
///
/// İki store da `SharedStores.terminals`/`settings` üzerinden türev üretir;
/// servis tarafı `ServiceRegistry.sleepAssertion` ve `processSampler`dır.
/// Toolbar katkısı `.statusTrailing` bölgesine iki descriptor'dır — kabuğun
/// `settings` öğesi `.statusLeading`e kabuk tarafından kaydedilir.
@MainActor
final class StatusBarFeatureAssembly: FeatureAssembly, ShellContributing {
    let bootstrapPhase = BootstrapPhase.ui

    private(set) var computerAwake: ComputerAwakeStore!
    private(set) var resourceUsage: ResourceUsageStore!

    func build(services: any ServiceRegistry, shared: SharedStores) {
        computerAwake = ComputerAwakeStore(
            terminals: shared.terminals,
            settings: shared.settings,
            assertion: services.sleepAssertion
        )
        resourceUsage = ResourceUsageStore(
            terminals: shared.terminals,
            terminalService: services.terminal,
            sampler: services.processSampler
        )
    }

    func registerShellItems(into registries: ShellRegistries) {
        registries.toolbar.register(ToolbarItemDescriptor(
            id: .keepAwake,
            region: .statusTrailing,
            order: ShellToolbarItems.Order.keepAwake,
            makeView: { AnyView(KeepAwakeStatusItem()) }
        ))
        registries.toolbar.register(ToolbarItemDescriptor(
            id: .resourceManager,
            region: .statusTrailing,
            order: ShellToolbarItems.Order.resourceManager,
            makeView: { AnyView(ResourceManagerStatusItem()) }
        ))
    }

    func start() async {
        computerAwake.start()
        resourceUsage.start()
    }

    func shutdown() async {
        resourceUsage.stop()
        computerAwake.stop()
    }
}
