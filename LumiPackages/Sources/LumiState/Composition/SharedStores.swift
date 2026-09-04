import Foundation
import LumiKit

/// Birden çok feature'ın (ve uygulama kabuğunun) paylaştığı store'lar
/// (refactor 3.3).
///
/// Üyelik ölçütü tek bir soru: **store'a birden fazla feature ya da AppKit
/// kabuğu erişiyor mu?** Erişmiyorsa store feature assembly'sinin içinde kalır.
/// Bugünkü `AppContainer`'a göre:
///
/// | Store | Neden shared |
/// |---|---|
/// | `toasts` | Uygulamanın TEK hata lavabosu (karar 5); terminal/repo/git/dosya/ayar store'larının hepsine enjekte edilir |
/// | `workspace` | Navigasyon + layout otoritesi; repo, terminal ve UI feature'ları ile menü aksiyonları okur/yazar |
/// | `terminals` | Terminal feature'ı yazar; workspace (ctor), bildirim köprüsü, oturum devamı ve menü aksiyonları okur |
/// | `settings` | Config aynası; menü aksiyonu (`aiProvider.launchCommand`) ve Settings ekranı okur |
///
/// Feature'a ait kalanlar: `promptQueue` (terminal), `repoStore`/`gitStore`/
/// `fileViewer` (repo), `usageStores`/`usageAutoRefresh` (usage),
/// `sessionSchedule` (zamanlanmış oturum).
@MainActor
public final class SharedStores {
    public let toasts: ToastStore
    public let workspace: WorkspaceStore
    public let terminals: TerminalListStore
    public let settings: SettingsStore

    /// Workspace facade'ının alt store'ları (refactor 5.2). Faz 6'da
    /// `ShellContext` bunları doğrudan alacak ve facade kalkacak.
    public var navigation: NavigationStore { workspace.navigation }
    public var layout: LayoutStore { workspace.layout }
    public var dialogs: DialogRouter { workspace.dialogs }

    public init(
        toasts: ToastStore,
        workspace: WorkspaceStore,
        terminals: TerminalListStore,
        settings: SettingsStore
    ) {
        self.toasts = toasts
        self.workspace = workspace
        self.terminals = terminals
        self.settings = settings
    }

    /// Servis stream'i tüketen paylaşılan store'lar. Sahipsiz kalmasınlar diye
    /// yaşam döngülerini `AppContainer` yürütür (feature bilgisi gerektirmez).
    public var lifecycles: [any StoreLifecycle] { [terminals, settings] }

    /// Somut servislerden bağımsız kurulum: sıra `WorkspaceStore`'un
    /// `terminals`'a bağımlılığından gelir.
    public static func make(
        config: any ConfigServicing,
        terminal: any TerminalSessionControlling,
        toastAutoDismissAfter: TimeInterval? = nil
    ) -> SharedStores {
        let toasts = toastAutoDismissAfter.map { ToastStore(autoDismissAfter: $0) } ?? ToastStore()
        let terminals = TerminalListStore(service: terminal, toasts: toasts)
        return SharedStores(
            toasts: toasts,
            workspace: WorkspaceStore(config: config, terminals: terminals),
            terminals: terminals,
            settings: SettingsStore(config: config, toasts: toasts)
        )
    }

    public func start() async {
        for store in lifecycles {
            await store.start()
        }
    }

    public func stop() {
        for store in lifecycles {
            store.stop()
        }
    }
}
