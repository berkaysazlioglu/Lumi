import Foundation
import LumiKit
import Observation

/// Açık tab'lar + aktif route (refactor 5.1/5.2; design/03 §4).
///
/// Tab kimliği repo PATH'idir (ad-çakışması bug fix'i, karar 11); eski
/// ad-tabanlı ui-state okunurken tek seferlik ad→path migration yapılır.
///
/// Persist (karar 9): `UIState.openTabs` + `UIState.activeTab` yazılmaya devam
/// eder. `activeTab` yalnız `.repo` route'unun projeksiyonudur; repo-dışı
/// route'lar (Faz 6) additive `UIState.activeRoute` anahtarına yazılır (K34) —
/// bkz. `persist()`.
@Observable
@MainActor
public final class NavigationStore {
    public private(set) var openTabs: [String] = []
    public private(set) var activeRoute: WorkspaceRoute = .none

    /// Proje yolu → o projede en son aktif olan checkout (karar 65).
    /// İndeksli kısayol bir projeye atlarken buradan okur.
    public private(set) var lastCheckouts: [String: String] = [:]

    /// **Proje köprüsü (karar 65).** `SharedStores` proje store'unu tanımaz —
    /// tanısaydı kabuk, repo feature'ına bağlanırdı (karar 33). Bunun yerine
    /// `RepoFeatureAssembly` iki okuma closure'ı enjekte eder; navigasyon
    /// projeleri bilir ama projelere BAĞIMLI değildir. Enjekte edilmemişse
    /// (headless test, proje feature'ı olmayan kompozisyon) proje gezinmesi
    /// sessizce devre dışıdır, tab davranışı aynen çalışır.
    @ObservationIgnored public var projectOrder: (() -> [String])?
    /// Proje yolu → o projeye ait checkout yolları (kök + yönetilen worktree'ler),
    /// panelde göründükleri sırada.
    @ObservationIgnored public var projectCheckouts: ((String) -> [String])?

    /// `.repo` route'unun adaptörü (12+ çağrı yeri kademeli taşınır).
    public var activeRepoPath: String? { activeRoute.repoPath }

    /// Aktif REPO değişimi: watch/unwatch + git veri yüklemesi köprüsü
    /// (eski repo, yeni repo). Yalnız `.repo` geçişlerinde ateşlenir —
    /// repo → repo-dışı route geçişi `(old, nil)` olarak bildirilir.
    @ObservationIgnored public var onActiveRepoChanged: ((String?, String?) -> Void)?

    /// Tab kapanışı: repo'ya ait BELLEK cache'lerini boşaltma sinyali
    /// (refactor 5.5). Persist edilen `projectGridLayouts` bu yoldan
    /// TEMİZLENMEZ — kullanıcı tercihidir (karar 9).
    @ObservationIgnored public var onTabClosed: ((String) -> Void)?

    @ObservationIgnored private let config: any ConfigServicing
    @ObservationIgnored private let terminals: any TerminalFocusCoordinating
    /// Faz 6.3 route geçiş sözleşmesinin AppKit yüzü. Opsiyonel: view köprüsü
    /// olmayan bir kompozisyonda (birim testleri, headless) navigasyon aynen
    /// çalışır.
    @ObservationIgnored private let viewProvider: (any TerminalViewProviding)?
    /// Persist zincirinin kuyruğu (sıra garantisi için önceki yazım beklenir).
    @ObservationIgnored private var pendingPersistTask: Task<Void, Never>?

    public init(
        config: any ConfigServicing,
        terminals: any TerminalFocusCoordinating,
        viewProvider: (any TerminalViewProviding)? = nil
    ) {
        self.config = config
        self.terminals = terminals
        self.viewProvider = viewProvider
    }

    // MARK: - Yükleme / migration

    /// Bootstrap sözleşmesi: repos yüklendikten SONRA çağrılır — ad→path tab
    /// migration'ı repo listesini okur. Dönüş: legacy grid migration'ı için
    /// `LayoutStore`'a geçirilecek açık tab listesi.
    @discardableResult
    public func load(state: UIState, repos: [Repo]) -> [String] {
        lastCheckouts = state.lastCheckouts
        var seenTabs = Set<String>()
        openTabs = state.openTabs.compactMap { entry -> String? in
            if repos.contains(where: { $0.path == entry }) {
                return entry
            }
            // Legacy: tab repo ADI olarak yazılmış olabilir
            return repos.first(where: { $0.name == entry })?.path
        }.filter { seenTabs.insert($0).inserted }

        activeRoute = Self.restoreRoute(from: state, resolvedTab: resolveActiveTab(state.activeTab, repos: repos))

        if let scope = activeRoute.terminalScope {
            terminals.activateSurface(scope)
        }
        announceRepoChange(from: .none, to: activeRoute)
        return openTabs
    }

    /// K34: repo-dışı route diskte `activeRoute` ile yaşar ve `activeTab`'ı
    /// EZER (repo tab'ındayken `activeRoute` null yazıldığı için çakışma olmaz).
    private static func restoreRoute(from state: UIState, resolvedTab: String?) -> WorkspaceRoute {
        if let raw = state.activeRoute, !raw.isEmpty {
            return .content(ContentRouteID(rawValue: raw))
        }
        return WorkspaceRoute(repoPath: resolvedTab)
    }

    private func resolveActiveTab(_ stored: String?, repos: [Repo]) -> String? {
        guard let stored else { return nil }
        if openTabs.contains(stored) { return stored }
        if let migrated = repos.first(where: { $0.name == stored })?.path,
           openTabs.contains(migrated) {
            return migrated
        }
        return openTabs.first
    }

    // MARK: - Tab / route yönetimi

    public func openTab(_ repoPath: String) {
        if !openTabs.contains(repoPath) {
            openTabs.append(repoPath)
        }
        setRoute(.repo(repoPath))
    }

    public func setRoute(_ route: WorkspaceRoute) {
        let previous = activeRoute
        activeRoute = route
        rememberCheckout(route.repoPath)
        applySurfaceTransition(from: previous, to: route)
        persist()
        announceRepoChange(from: previous, to: route)
    }

    /// **Faz 6.3 route geçiş sözleşmesi** (view'da DEĞİL, burada). Karar 103:
    /// "terminal yüzeyi" artık repo route'u VE All Terminals'tır
    /// (`WorkspaceRoute.terminalScope`):
    ///
    /// | Geçiş | Terminal yüzeyi | View köprüsü |
    /// |---|---|---|
    /// | yüzey → yüzey-dışı route | `deactivateSurface()` (arka plan + odak yok) | `detachAll()` |
    /// | yüzey-dışı route → yüzey | `activateSurface()` (foreground + odak) | `refreshAttachedViews()` |
    /// | yüzey → yüzey (repo ⇄ repo ⇄ All) | `activateSurface()` (eskiyi arkaya, yeniyi öne) | — (host'lar yerinde) |
    /// | yüzey-dışı → yüzey-dışı | — | — |
    ///
    /// PTY hiçbir adımda durmaz, view'lar yok edilmez: detach yalnız reparent
    /// eder (design/03 §3). Yüzeyler arası geçişte kartlar yeni ızgaranın
    /// host'larına SwiftUI'nin attach/dismantle yoluyla taşınır.
    private func applySurfaceTransition(from previous: WorkspaceRoute, to route: WorkspaceRoute) {
        if let scope = route.terminalScope {
            terminals.activateSurface(scope) // cross-store yan etki
            if previous.contentRouteID != nil, previous.terminalScope == nil {
                // Terminaller detach edilmişti: canlı view'lar yeniden oturtulur.
                viewProvider?.refreshAttachedViews()
            }
            return
        }
        guard previous.terminalScope != nil else { return }
        terminals.deactivateSurface()
        viewProvider?.detachAll()
    }

    // MARK: - Serbest terminaller (karar 108)

    /// Yol hiçbir projenin checkout'u (kök + yönetilen workspace'ler) ya da
    /// açık bir tab değilse serbesttir. Proje köprüsü enjekte edilmemişse
    /// yalnız `openTabs` sahiplik sayılır.
    public func isLooseTerminalPath(_ path: String) -> Bool {
        let checkouts = (projectOrder?() ?? []).flatMap { projectCheckouts?($0) ?? [$0] }
        return LooseTerminalRule.isLoose(
            path: path, projectPaths: checkouts, workspacePaths: [], openTabs: openTabs
        )
    }

    /// Terminale gitmenin TEK kapısı: serbest terminal hiçbir zaman repo tab'ı
    /// olmaz — `openTab(~)` aktif repo köprüsünü (`onActiveRepoChanged`) ev
    /// dizini için ateşler, dosya izleyici + ağaç taraması + git yüklemesi
    /// başlar ve sağ panel `~` için açılırdı. Serbest terminal All Terminals'ta
    /// öne gelir; checkout terminali bugünkü gibi kendi repo'suna geçer.
    public func openTerminalSurface(for repoPath: String) {
        if isLooseTerminalPath(repoPath) {
            if activeRoute.terminalScope != .all { setRoute(.content(.allTerminals)) }
        } else if activeRepoPath != repoPath {
            openTab(repoPath)
        }
    }

    // MARK: - Proje gezinmesi (karar 65)

    /// `index` (0 tabanlı) sıradaki projeye geçer: o projede en son kullanılan
    /// checkout açılır, yoksa projenin kendi kökü.
    ///
    /// İndeks PROJELERE vurur, görünen satırlara değil — proje daraltılıp
    /// genişletildikçe kısayolun anlamı değişmesin diye (karar 65).
    public func openProject(at index: Int) {
        guard let projects = projectOrder?(), projects.indices.contains(index) else { return }
        openTab(checkoutToOpen(in: projects[index]))
    }

    /// Bir projeye geçerken açılacak checkout. Hatırlanan checkout artık o
    /// projeye ait değilse (worktree silinmiş olabilir) projenin köküne düşer.
    public func checkoutToOpen(in projectPath: String) -> String {
        guard let remembered = lastCheckouts[projectPath] else { return projectPath }
        let checkouts = projectCheckouts?(projectPath) ?? [projectPath]
        return checkouts.contains(remembered) ? remembered : projectPath
    }

    /// Bir checkout'un ait olduğu proje. Checkout'un kendisi bir projeyse o döner.
    public func projectPath(containing checkout: String) -> String? {
        guard let projects = projectOrder?() else { return nil }
        if projects.contains(checkout) { return checkout }
        return projects.first { (projectCheckouts?($0) ?? []).contains(checkout) }
    }

    private func rememberCheckout(_ checkout: String?) {
        guard let checkout, let project = projectPath(containing: checkout) else { return }
        guard lastCheckouts[project] != checkout else { return }
        lastCheckouts[project] = checkout
    }

    /// Guard: minimize edilmiş terminali olan tab dialog'suz kapanmaz —
    /// dialog GEREKİYORSA `nil` yerine sayı döner, sunumu `DialogRouter` yapar.
    /// Dönüş `nil` = tab kapatıldı.
    public func requestCloseTab(_ repoPath: String) -> Int? {
        let minimizedCount = terminals.minimizedTerminals(in: repoPath).count
        if minimizedCount > 0 { return minimizedCount }
        closeTab(repoPath)
        return nil
    }

    public func closeTab(_ repoPath: String) {
        let wasActive = activeRoute.repoPath == repoPath
        openTabs.removeAll { $0 == repoPath }
        if wasActive {
            // Kapanan aktifse listenin SON tab'ı aktif olur
            activeRoute = WorkspaceRoute(repoPath: openTabs.last)
            if let tab = activeRoute.repoPath {
                terminals.activateSurface(.repo(tab))
            } else {
                terminals.focus(nil)
            }
        }
        terminals.closeAll(in: repoPath)
        persist()
        if wasActive {
            onActiveRepoChanged?(repoPath, activeRoute.repoPath)
        } else {
            onActiveRepoChanged?(repoPath, nil) // unwatch için kapanan repo bildirilir
        }
        onTabClosed?(repoPath)
    }

    // MARK: - Köprüler

    /// `onActiveRepoChanged` YALNIZ `.repo` ekseninde konuşur: repo-dışı bir
    /// route'a geçişte hedef `nil`'dir (izleyici unwatch eder), repo-dışından
    /// repo-dışına geçişte hiç ateşlenmez.
    private func announceRepoChange(from previous: WorkspaceRoute, to current: WorkspaceRoute) {
        let old = previous.repoPath
        let new = current.repoPath
        guard old != new, old != nil || new != nil else { return }
        onActiveRepoChanged?(old, new)
    }

    // MARK: - Persistence

    /// Yazımlar tek zincirde serileştirilir (1.17): geç kalan BAYAT snapshot en
    /// son diske inmesin.
    private func persist() {
        let tabs = openTabs
        // Karar 9: `activeTab` repo path yazmaya devam eder (Electron paritesi).
        // K34 (additive): repo-dışı route ayrı `activeRoute` anahtarına yazılır;
        // repo route'unda null olur, böylece iki alan asla çelişmez.
        let active = activeRoute.repoPath
        let routeID = activeRoute.contentRouteID?.rawValue
        let checkouts = lastCheckouts
        let previous = pendingPersistTask
        pendingPersistTask = Task { [config] in
            await previous?.value
            await config.updateUIState { state in
                state.openTabs = tabs
                state.activeTab = active
                state.activeRoute = routeID
                state.lastCheckouts = checkouts
            }
        }
    }
}
