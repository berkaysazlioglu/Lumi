import Foundation
import LumiKit
import LumiState
import LumiUI
import SwiftUI

/// Orchestrator (karar 103): tüm ajan terminallerini yöneten sohbet.
///
/// Top bar butonu + %80'lik popup kabuğa buradan kaydedilir. Süreç açılışta
/// BAŞLAMAZ — popup ilk açıldığında ya da ilk mesajda tembel başlar; quit'te
/// sonlandırılır (konuşma transkriptte kalır, sonraki açılış resume eder).
@MainActor
final class OrchestratorFeatureAssembly: FeatureAssembly, ShellContributing {
    let bootstrapPhase = BootstrapPhase.ui

    private(set) var orchestrator: OrchestratorStore!

    func build(services: any ServiceRegistry, shared: SharedStores) {
        orchestrator = OrchestratorStore(service: services.orchestrator, config: services.config)
    }

    func registerShellItems(into registries: ShellRegistries) {
        registries.overlays.register(OverlayDescriptor(
            id: .orchestrator,
            isPresented: { $0.dialogs.isOrchestratorOpen },
            makeView: { AnyView(OrchestratorOverlay()) }
        ))
        registries.toolbar.register(ToolbarItemDescriptor(
            id: .orchestrator,
            region: .trailing,
            order: ShellToolbarItems.Order.orchestrator,
            makeView: { AnyView(OrchestratorToolbarItem()) }
        ))
    }

    func start() async {}

    func shutdown() async {
        await orchestrator.shutdown()
    }
}
