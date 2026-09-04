//
//  GEÇİCİ FACADE — Faz 6'da KALKACAK.
//
//  `WorkspaceStore` artık durum tutmaz: `NavigationStore` + `LayoutStore` +
//  `DialogRouter` üçlüsünün önünde duran bir adaptördür (refactor 5.2). Tek
//  varlık nedeni LumiUI'ın (RootView/HeaderBar/RepoTabStrip/SettingsView/
//  FocusModeBar) ve AppKit kabuğunun bugünkü API'yi çağırmaya devam etmesidir.
//  Faz 6.1'de `ShellContext` gelip view'lar alt store'ları doğrudan okuyunca
//  bu dosya silinir. **Buraya YENİ davranış eklenmez** — yeni iş alt
//  store'lara yazılır, facade yalnız delege eder.
//

import Foundation
import LumiKit
import Observation

@Observable
@MainActor
public final class WorkspaceStore {
    /// Yeni repo default'u: tek kolon + Fit (karar 31).
    public static let defaultGridLayout = LayoutStore.defaultGridLayout

    /// Facade'ın önünde durduğu alt store'lar (Faz 6 `ShellContext` bunları
    /// doğrudan alacak).
    public let navigation: NavigationStore
    public let layout: LayoutStore
    public let dialogs: DialogRouter

    @ObservationIgnored private let config: any ConfigServicing
    @ObservationIgnored private let terminals: any TerminalFocusCoordinating

    public typealias CloseTabDialogState = LumiState.CloseTabDialogState

    public init(config: any ConfigServicing, terminals: any TerminalFocusCoordinating) {
        self.config = config
        self.terminals = terminals
        navigation = NavigationStore(config: config, terminals: terminals)
        layout = LayoutStore(config: config) { [terminals] id, repoPath in
            terminals.visibleTerminals(in: repoPath).contains { $0.id == id }
        }
        dialogs = DialogRouter()
    }

    // MARK: - Navigasyon (delegasyon)

    public var openTabs: [String] { navigation.openTabs }
    public var activeRoute: WorkspaceRoute { navigation.activeRoute }
    /// Legacy adaptör: `.repo(p)` → `p`, diğer route'lar → `nil`.
    public var activeTab: String? { navigation.activeRepoPath }

    /// Aktif repo değişiminde watch/unwatch + git veri yüklemesi için container
    /// köprüsü (eski değer, yeni değer).
    public var onActiveRepoChanged: ((String?, String?) -> Void)? {
        get { navigation.onActiveRepoChanged }
        set { navigation.onActiveRepoChanged = newValue }
    }

    /// Tab kapanışında repo'ya ait bellek cache'lerini boşaltma sinyali (5.5).
    public var onTabClosed: ((String) -> Void)? {
        get { navigation.onTabClosed }
        set { navigation.onTabClosed = newValue }
    }

    /// Bootstrap sözleşmesi: repos yüklendikten SONRA çağrılır —
    /// ad→path tab migration'ı ve legacy gridColumns migration'ı repo listesini okur.
    public func load(repos: [Repo]) async {
        let state = await config.uiState()
        // SIRA: layout migration'ı navigation'ın ürettiği tab listesini okur;
        // `onActiveRepoChanged` ise iki yükleme de bittikten sonra ateşlenmeli.
        let tabs = navigation.load(state: state, repos: repos)
        layout.load(state: state, openTabs: tabs)
    }

    public func openTab(_ repoPath: String) {
        navigation.openTab(repoPath)
    }

    public func setActiveTab(_ repoPath: String) {
        navigation.setRoute(.repo(repoPath))
    }

    public func setRoute(_ route: WorkspaceRoute) {
        navigation.setRoute(route)
    }

    /// Guard: minimize edilmiş terminali olan tab dialog'suz kapanmaz.
    public func requestCloseTab(_ repoPath: String, repoName: String) {
        guard let minimizedCount = navigation.requestCloseTab(repoPath) else { return }
        dialogs.present(.closeTab(CloseTabDialogState(
            repoPath: repoPath,
            repoName: repoName,
            minimizedCount: minimizedCount
        )))
    }

    public func confirmCloseTab() {
        guard let dialog = dialogs.closeTabDialog else { return }
        dialogs.dismiss()
        navigation.closeTab(dialog.repoPath)
    }

    public func cancelCloseTab() {
        guard dialogs.closeTabDialog != nil else { return }
        dialogs.dismiss()
    }

    // MARK: - Layout (delegasyon)

    public var leftSidebarOpen: Bool { layout.leftSidebarOpen }
    public var rightSidebarOpen: Bool { layout.rightSidebarOpen }
    public var projectGridLayouts: [String: GridLayout] { layout.projectGridLayouts }
    public var maximizedByRepo: [String: TerminalID] { layout.maximizedByRepo }
    public var isFocusMode: Bool { layout.isFocusMode }

    /// Traffic-light gizleme AppKit tarafında bu callback ile senkronlanır.
    public var onFocusModeChanged: ((Bool) -> Void)? {
        get { layout.onFocusModeChanged }
        set { layout.onFocusModeChanged = newValue }
    }

    public func toggleFocusMode() { layout.toggleFocusMode() }
    public func exitFocusMode() { layout.exitFocusMode() }
    public func toggleLeftSidebar() { layout.toggleLeftSidebar() }
    public func toggleRightSidebar() { layout.toggleRightSidebar() }
    public func setLeftSidebarOpen(_ open: Bool) { layout.setLeftSidebarOpen(open) }
    public func setRightSidebarOpen(_ open: Bool) { layout.setRightSidebarOpen(open) }

    public func gridLayout(for repoPath: String?) -> GridLayout {
        layout.gridLayout(for: repoPath)
    }

    public func setGridLayout(_ newLayout: GridLayout, for repoPath: String) {
        layout.setGridLayout(newLayout, for: repoPath)
    }

    /// Maximize odak da verir — odaklama terminal store'unun işidir, layout
    /// yalnız görünürlüğü doğrular.
    public func maximize(_ id: TerminalID, in repoPath: String) {
        guard layout.maximize(id, in: repoPath) else { return }
        terminals.focus(id)
    }

    public func toggleMaximize(_ id: TerminalID, in repoPath: String) {
        if layout.isMaximized(id, in: repoPath) {
            layout.restoreMaximize(in: repoPath)
        } else {
            maximize(id, in: repoPath)
        }
    }

    public func restoreMaximize(in repoPath: String) {
        layout.restoreMaximize(in: repoPath)
    }

    public func maximizedTerminal(in repoPath: String) -> TerminalID? {
        layout.maximizedTerminal(in: repoPath)
    }

    // MARK: - Dialog bayrak adaptörleri (delegasyon)

    public var isRepoSelectorOpen: Bool {
        get { dialogs.isPresenting(.repoSelector) }
        set { newValue ? dialogs.present(.repoSelector) : dialogs.dismiss(.repoSelector) }
    }

    public var isSettingsOpen: Bool {
        get { dialogs.isPresenting(.settings) }
        set { newValue ? dialogs.present(.settings) : dialogs.dismiss(.settings) }
    }

    public var isOnboardingActive: Bool {
        get { dialogs.isPresenting(.onboarding) }
        set { newValue ? dialogs.present(.onboarding) : dialogs.dismiss(.onboarding) }
    }

    public var collapsedRepoGroups: Set<String> {
        get { dialogs.collapsedRepoGroups }
        set { dialogs.collapsedRepoGroups = newValue }
    }

    public var closeTabDialog: CloseTabDialogState? { dialogs.closeTabDialog }
    public var quitDialogTerminalCount: Int? { dialogs.quitDialogTerminalCount }
    public var isInputBlockingOverlayOpen: Bool { dialogs.isInputBlockingOverlayOpen }

    /// Quit-onay çözümü app delegate'e köprülenir (.terminateLater akışı).
    public var onQuitResolved: ((Bool) -> Void)? {
        get { dialogs.onQuitResolved }
        set { dialogs.onQuitResolved = newValue }
    }

    public func presentQuitDialog(terminalCount: Int) {
        dialogs.presentQuitDialog(terminalCount: terminalCount)
    }

    public func resolveQuit(_ shouldQuit: Bool) {
        dialogs.resolveQuit(shouldQuit)
    }
}
