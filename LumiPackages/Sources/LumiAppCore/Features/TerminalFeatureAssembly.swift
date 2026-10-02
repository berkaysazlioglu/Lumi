import Foundation
import LumiKit
import LumiState
import LumiUI
import SwiftUI

/// Terminal özelliği (refactor 3.3): prompt kuyruğu, görünüm ayarlarının canlı
/// uygulanması ve kapanışta PTY temizliği.
///
/// `.system` fazı: hiçbir spawn bu assembly'den önce olamaz — `AppContainer`
/// prelude'ünde `fixProcessPath()` koşar, sonra ilk faz burasıdır.
@MainActor
final class TerminalFeatureAssembly: FeatureAssembly, ShellContributing {
    let bootstrapPhase = BootstrapPhase.system

    private(set) var promptQueue: PromptQueueStore!
    private var services: (any ServiceRegistry)!
    private var shared: SharedStores!

    func build(services: any ServiceRegistry, shared: SharedStores) {
        self.services = services
        self.shared = shared
        promptQueue = PromptQueueStore(service: services.terminal, toasts: shared.toasts)
    }

    /// Faz 6.6: orta alanın terminals route'u BU assembly'nin katkısıdır.
    /// Karar 55: Sessions panel öğesi kaldırıldı — canlı ajanlar Projects
    /// panelinde checkout başına listeleniyor.
    func registerShellItems(into registries: ShellRegistries) {
        registries.routes.register(ContentRouteDescriptor(
            id: .terminals,
            title: "Terminals",
            icon: "terminal",
            makeView: { repoPath in AnyView(TerminalsRouteView(repoPath: repoPath)) }
        ))
        // Karar 103: tüm projelerin terminalleri — aynı görünüm, `.all` kapsamı.
        registries.routes.register(ContentRouteDescriptor(
            id: .allTerminals,
            title: AllTerminalsRoute.title,
            icon: AllTerminalsRoute.icon,
            makeView: { _ in AnyView(TerminalsRouteView(scope: .all)) }
        ))
        registries.toolbar.register(ToolbarItemDescriptor(
            id: ToolbarItemID("route.allTerminals"),
            region: .center,
            order: ShellToolbarItems.Order.routeTitle,
            isVisible: { $0.navigation.activeRoute == AllTerminalsRoute.route },
            makeView: {
                AnyView(RouteTitleToolbarItem(title: AllTerminalsRoute.title, icon: AllTerminalsRoute.icon))
            }
        ))
        // Üretim bölgesi (Faz 6.4): grid ayarı + Edit her terminal yüzeyinde
        // (repo ya da All Terminals); birincil CTA yalnız repo route'unda —
        // spawn bir checkout ister. Repo-dışı bir route'ta (`.content`) veya
        // hiç tab yokken hepsi bar'dan düşer.
        registries.toolbar.register(ToolbarItemDescriptor(
            id: .gridSettings,
            region: .center,
            order: ShellToolbarItems.Order.gridSettings,
            isVisible: { $0.activeTerminalScope != nil },
            makeView: { AnyView(GridSettingsToolbarItem()) }
        ))
        registries.toolbar.register(ToolbarItemDescriptor(
            id: .arrangeTerminals,
            region: .center,
            order: ShellToolbarItems.Order.arrangeTerminals,
            isVisible: { $0.activeTerminalScope != nil },
            makeView: { AnyView(ArrangeTerminalsToolbarItem()) }
        ))
        registries.toolbar.register(ToolbarItemDescriptor(
            id: .newTerminal,
            region: .center,
            order: ShellToolbarItems.Order.newTerminal,
            isVisible: { $0.activeRepoPath != nil },
            makeView: { AnyView(NewTerminalToolbarItem()) }
        ))
    }

    func start() async {
        let config = await services.config.config()
        applyAppearance(config)
        shared.terminals.applyAutoMinimize(config.autoMinimizeOnSend)
        promptQueue.start()
    }

    /// Font/cursor callback dansı (eski `ConfigSideEffectCoordinator` +
    /// `AppContainer.rebuildFont` ikilisi) burada tek bloğa indi: yeni değer
    /// zaten elimizde, taze config'i yeniden okumaya gerek yok.
    func configDidChange(old: AppConfig, new: AppConfig) {
        // Aile ve boyut TEK NSFont'a birlikte çözülür — hangisi değişirse değişsin
        // font yeniden kurulur.
        if old.terminalFontFamily != new.terminalFontFamily
            || old.terminalFontSize != new.terminalFontSize {
            applyFont(new)
        }
        if old.terminalCursorStyle != new.terminalCursorStyle
            || old.terminalCursorBlink != new.terminalCursorBlink {
            applyCursor(new)
        }
        // Karar 57
        if old.terminalLinkActionsEnabled != new.terminalLinkActionsEnabled {
            services.terminal.applyLinkActions(enabled: new.terminalLinkActionsEnabled)
        }
        // Karar 24
        if old.autoMinimizeOnSend != new.autoMinimizeOnSend {
            shared.terminals.applyAutoMinimize(new.autoMinimizeOnSend)
        }
    }

    func shutdown() async {
        promptQueue.stop()
        services.terminal.killAll()
        // Global NSEvent monitörleri (klavye/odak) bırakılır — sızıntı önlemi.
        services.terminal.shutdown()
    }

    // MARK: - Görünüm

    private func applyAppearance(_ config: AppConfig) {
        applyFont(config)
        applyCursor(config)
        services.terminal.applyLinkActions(enabled: config.terminalLinkActionsEnabled)
    }

    /// Karar 61: kullanıcının font boyutu ayarı arayüz ölçeğiyle ÇARPILIR —
    /// SwiftTerm SwiftUI token'larını kullanmadığı için ölçek ona ayrıca iner.
    private func applyFont(_ config: AppConfig) {
        services.terminal.applyFont(LumiFonts.mono(
            family: config.terminalFontFamily,
            size: Theme.scaled(CGFloat(config.terminalFontSize))
        ))
    }

    private func applyCursor(_ config: AppConfig) {
        services.terminal.applyCursor(
            shape: TerminalCursorShape.parse(config.terminalCursorStyle),
            blink: config.terminalCursorBlink
        )
    }
}
