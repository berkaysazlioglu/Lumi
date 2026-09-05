import Foundation
import LumiKit

/// Birden çok feature'ın (ve uygulama kabuğunun) paylaştığı store'lar
/// (refactor 3.3).
///
/// Üyelik ölçütü tek bir soru: **store'a birden fazla feature ya da AppKit
/// kabuğu erişiyor mu?** Erişmiyorsa store feature assembly'sinin içinde kalır.
///
/// | Store | Neden shared |
/// |---|---|
/// | `toasts` | Uygulamanın TEK hata lavabosu (karar 5); terminal/repo/git/dosya/ayar store'larının hepsine enjekte edilir |
/// | `navigation` | Açık tab'lar + aktif route; repo feature'ı, menü aksiyonları ve kabuk okur/yazar |
/// | `layout` | Panel yerleşimi/görünürlüğü, grid, maximize, focus mode; menü + kabuk + Settings |
/// | `dialogs` | Modal otoritesi; quit akışı AppKit'ten, diğerleri kabuktan sürülür |
/// | `terminals` | Terminal feature'ı yazar; navigasyon (ctor), bildirim köprüsü, oturum devamı ve menü aksiyonları okur |
/// | `settings` | Config aynası; menü aksiyonu (`aiProvider.launchCommand`) ve Settings ekranı okur |
///
/// Feature'a ait kalanlar: `promptQueue` (terminal), `repoStore`/`gitStore`/
/// `fileViewer` (repo), `usageStores`/`usageAutoRefresh` (usage),
/// `sessionSchedule` (zamanlanmış oturum).
///
/// **Faz 6.1:** `WorkspaceStore` facade'ı kaldırıldı — üç alt store artık
/// doğrudan burada durur ve `ShellContext` üzerinden view'lara ulaşır.
@MainActor
public final class SharedStores {
    public let toasts: ToastStore
    public let navigation: NavigationStore
    public let layout: LayoutStore
    public let dialogs: DialogRouter
    public let terminals: TerminalListStore
    public let settings: SettingsStore

    public init(
        toasts: ToastStore,
        navigation: NavigationStore,
        layout: LayoutStore,
        dialogs: DialogRouter,
        terminals: TerminalListStore,
        settings: SettingsStore
    ) {
        self.toasts = toasts
        self.navigation = navigation
        self.layout = layout
        self.dialogs = dialogs
        self.terminals = terminals
        self.settings = settings
    }

    /// Servis stream'i tüketen paylaşılan store'lar. Sahipsiz kalmasınlar diye
    /// yaşam döngülerini `AppContainer` yürütür (feature bilgisi gerektirmez).
    public var lifecycles: [any StoreLifecycle] { [terminals, settings] }

    /// Somut servislerden bağımsız kurulum: sıra `NavigationStore`/`LayoutStore`'un
    /// `terminals`'a bağımlılığından gelir.
    public static func make(
        config: any ConfigServicing,
        terminal: any TerminalSessionControlling,
        viewProvider: (any TerminalViewProviding)? = nil,
        toastAutoDismissAfter: TimeInterval? = nil
    ) -> SharedStores {
        let toasts = toastAutoDismissAfter.map { ToastStore(autoDismissAfter: $0) } ?? ToastStore()
        let terminals = TerminalListStore(service: terminal, toasts: toasts)
        return SharedStores(
            toasts: toasts,
            navigation: NavigationStore(
                config: config,
                terminals: terminals,
                viewProvider: viewProvider
            ),
            layout: LayoutStore(
                config: config,
                isTerminalVisible: { [terminals] id, repoPath in
                    terminals.visibleTerminals(in: repoPath).contains { $0.id == id }
                },
                focusTerminal: { [terminals] id in terminals.focus(id) }
            ),
            dialogs: DialogRouter(),
            terminals: terminals,
            settings: SettingsStore(config: config, toasts: toasts)
        )
    }

    /// Bootstrap sözleşmesi: repos yüklendikten SONRA çağrılır — ad→path tab
    /// migration'ı repo listesini okur.
    ///
    /// **SIRA bağlayıcıdır:** layout migration'ı (`gridColumns` fan-out'u)
    /// navigation'ın ürettiği tab listesini okur, bu yüzden tek `uiState()`
    /// okumasıyla önce navigation, sonra layout yüklenir.
    public func loadWorkspace(state: UIState, repos: [Repo]) {
        let tabs = navigation.load(state: state, repos: repos)
        layout.load(state: state, openTabs: tabs)
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
