import Foundation
import LumiKit
import LumiState
import LumiUI
import SwiftUI

/// Bir feature'ın kabuğa yaptığı katkı (Faz 6.6).
///
/// `FeatureAssembly` LumiState'te yaşar ve LumiUI'ı GÖREMEZ (modül grafiği);
/// bu yüzden kabuk katkısı ayrı, LumiAppCore'a ait bir protokoldür. Bir
/// assembly katkı vermiyorsa protokolü hiç uygulamaz.
@MainActor
protocol ShellContributing {
    /// Panel öğeleri / route'lar / overlay'ler burada kaydedilir.
    func registerShellItems(into registries: ShellRegistries)
}

/// Kabuğun kompozisyonu (Faz 6.6).
///
/// **Descriptor tipleri LumiUI'da, KÜMESİ burada.** Yeni bir özellik eklemek
/// için kabuk dosyalarının hiçbirine dokunulmaz:
/// `TasksAssembly: FeatureAssembly, ShellContributing` yazılır,
/// `registerShellItems`'ta `registries.routes.register(...)` denir ve
/// `AppComposition.live`'daki assembly listesine bir satır eklenir.
@MainActor
struct ShellComposition {
    let registries: ShellRegistries
    let context: ShellContext

    static func make(
        registry: LiveServiceRegistry,
        shared: SharedStores,
        repo: RepoFeatureAssembly,
        terminal: TerminalFeatureAssembly,
        usage: UsageFeatureAssembly,
        sessionSchedule: SessionScheduleAssembly,
        workspaceBoot: WorkspaceBootAssembly,
        statusBar: StatusBarFeatureAssembly,
        contributors: [any ShellContributing]
    ) -> ShellComposition {
        let registries = makeRegistries(contributors: contributors)

        let context = ShellContext(
            navigation: shared.navigation,
            layout: shared.layout,
            dialogs: shared.dialogs,
            terminals: shared.terminals,
            repos: repo.repoStore,
            workspaces: repo.workspaceStore,
            git: repo.gitStore,
            plastic: repo.plasticStore,
            commitAssistant: repo.commitAssistant,
            agentHistory: repo.agentHistory,
            fileViewer: repo.fileViewer,
            settings: shared.settings,
            sessionSchedule: sessionSchedule.sessionSchedule,
            promptQueue: terminal.promptQueue,
            toasts: shared.toasts,
            onboarding: workspaceBoot.onboarding,
            usage: usage.usageStores,
            computerAwake: statusBar.computerAwake,
            resourceUsage: statusBar.resourceUsage,
            viewProvider: registry.viewProvider,
            highlighter: registry.highlighter,
            actions: makeActions(registry: registry, shared: shared, repo: repo)
        )
        return ShellComposition(registries: registries, context: context)
    }

    /// Kayıt defterinin kurulumu — servis grafiğinden BAĞIMSIZ.
    ///
    /// Sıra önemlidir: önce feature katkıları (panel öğeleri dahil), sonra
    /// kabuğun kendi öğeleri. Panel toggle'ları kayıtlı panel öğelerine
    /// baktığı için (`ShellToolbarItems.panelToggles`) toolbar kaydı en sonda
    /// yapılır.
    static func makeRegistries(contributors: [any ShellContributing]) -> ShellRegistries {
        let registries = ShellRegistries()
        // Karar 44: panelReveal İLK kayıt olmak zorunda — feature overlay'leri
        // (createWorkspace modalı, silme dialogu) de onun ÜSTÜNDE çizilir.
        registerPanelRevealOverlay(into: registries)
        for contributor in contributors {
            contributor.registerShellItems(into: registries)
        }
        registerShellOverlays(into: registries)
        registerShellToolbar(into: registries)
        return registries
    }

    /// Kabuğun KENDİ toolbar öğeleri — bir feature'a ait olmayanlar (panel
    /// yuvası toggle'ları, logo, tab şeridi, focus mode, settings).
    private static func registerShellToolbar(into registries: ShellRegistries) {
        registries.toolbar.register(contentsOf: ShellToolbarItems.core(panels: registries.panels))
    }

    /// Kabuğun KENDİ overlay'leri — bir feature'a ait olmayanlar (focus mode
    /// barı, dosya görüntüleyici, ayarlar, toast'lar, iki onay dialogu).
    /// Karar 44: İLK kayıt — diğer overlay'lerin (modal, toast, dialog) altında
    /// kalır. Yalnız en az bir yuva kenar hover'ına uygunken çizilir.
    private static func registerPanelRevealOverlay(into registries: ShellRegistries) {
        let panels = registries.panels
        registries.overlays.register(OverlayDescriptor(
            id: .panelReveal,
            isPresented: { shell in
                shell.activeRepoPath != nil
                    && PanelRevealOverlay.slots.contains { shell.layout.canAutoReveal($0) }
            },
            makeView: { AnyView(PanelRevealOverlay(registry: panels)) }
        ))
    }

    private static func registerShellOverlays(into registries: ShellRegistries) {
        registries.overlays.register(OverlayDescriptor(
            id: .focusModeBar,
            alignment: .top,
            isPresented: { $0.layout.isFocusMode && $0.activeRepoPath != nil },
            makeView: { AnyView(FocusModeBarOverlay()) }
        ))
        registries.overlays.register(OverlayDescriptor(
            id: .fileViewer,
            isPresented: { $0.fileViewer.isPresented },
            makeView: { AnyView(FileViewerOverlay()) }
        ))
        registries.overlays.register(OverlayDescriptor(
            id: .settings,
            isPresented: { $0.dialogs.isSettingsOpen },
            makeView: { AnyView(SettingsOverlay()) }
        ))
        registries.overlays.register(OverlayDescriptor(
            id: .toasts,
            alignment: .bottomTrailing,
            isPresented: { !$0.toasts.toasts.isEmpty },
            makeView: { AnyView(ToastOverlayHost()) }
        ))
        registries.overlays.register(OverlayDescriptor(
            id: .closeTabDialog,
            isPresented: { $0.dialogs.closeTabDialog != nil },
            makeView: { AnyView(CloseTabDialogOverlay()) }
        ))
        registries.overlays.register(OverlayDescriptor(
            id: .quitDialog,
            isPresented: { $0.dialogs.quitDialogTerminalCount != nil },
            makeView: { AnyView(QuitDialogOverlay()) }
        ))
    }

    /// View'lar servisleri asla görmez (design/00 §3): sistem etkileşimleri
    /// buradaki closure'lardan geçer.
    private static func makeActions(
        registry: LiveServiceRegistry,
        shared: SharedStores,
        repo: RepoFeatureAssembly
    ) -> ShellActions {
        ShellActions(
            chooseFolder: { await registry.system.chooseFolder() },
            reveal: { repoPath, relativePath in
                registry.system.revealInFinder(path: repoPath + "/" + relativePath)
            },
            trash: { repoPath, relativePath in
                Task { @MainActor in
                    await shared.toasts.reporting {
                        try await registry.system.trash(path: repoPath + "/" + relativePath)
                    }
                    await repo.repoStore.loadFileTree(repoPath)
                }
            },
            revealPath: { path in registry.system.revealInFinder(path: path) }
        )
    }
}
