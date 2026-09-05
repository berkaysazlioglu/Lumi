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
        var seenTabs = Set<String>()
        openTabs = state.openTabs.compactMap { entry -> String? in
            if repos.contains(where: { $0.path == entry }) {
                return entry
            }
            // Legacy: tab repo ADI olarak yazılmış olabilir
            return repos.first(where: { $0.name == entry })?.path
        }.filter { seenTabs.insert($0).inserted }

        activeRoute = Self.restoreRoute(from: state, resolvedTab: resolveActiveTab(state.activeTab, repos: repos))

        if let tab = activeRoute.repoPath {
            terminals.activateRepo(tab)
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
        applySurfaceTransition(from: previous, to: route)
        persist()
        announceRepoChange(from: previous, to: route)
    }

    /// **Faz 6.3 route geçiş sözleşmesi** (view'da DEĞİL, burada):
    ///
    /// | Geçiş | Terminal yüzeyi | View köprüsü |
    /// |---|---|---|
    /// | terminals → başka route | `deactivateSurface()` (arka plan + odak yok) | `detachAll()` |
    /// | başka route → terminals | `activateRepo()` (foreground + odak) | `refreshAttachedViews()` |
    /// | repo → repo | `activateRepo()` (eskiyi arkaya, yeniyi öne) | — (host'lar yerinde) |
    /// | route-dışı → route-dışı | — | — |
    ///
    /// PTY hiçbir adımda durmaz, view'lar yok edilmez: detach yalnız reparent
    /// eder (design/03 §3).
    private func applySurfaceTransition(from previous: WorkspaceRoute, to route: WorkspaceRoute) {
        if let repoPath = route.repoPath {
            terminals.activateRepo(repoPath) // cross-store yan etki
            if previous.contentRouteID != nil {
                // Terminaller detach edilmişti: canlı view'lar yeniden oturtulur.
                viewProvider?.refreshAttachedViews()
            }
            return
        }
        guard previous.isRepo else { return }
        terminals.deactivateSurface()
        viewProvider?.detachAll()
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
                terminals.activateRepo(tab)
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
        let previous = pendingPersistTask
        pendingPersistTask = Task { [config] in
            await previous?.value
            await config.updateUIState { state in
                state.openTabs = tabs
                state.activeTab = active
                state.activeRoute = routeID
            }
        }
    }
}
