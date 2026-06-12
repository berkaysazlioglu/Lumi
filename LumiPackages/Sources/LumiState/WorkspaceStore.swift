import Foundation
import LumiKit
import Observation

/// Tab/layout/dialog state'i (design/03 §4, spec/21 §9-13).
/// Tab kimliği repo PATH'idir (ad-çakışması bug fix'i, karar 11); eski
/// ad-tabanlı ui-state okunurken tek seferlik ad→path migration yapılır.
@Observable
@MainActor
public final class WorkspaceStore {
    public static let defaultGridLayout = GridLayout(mode: .auto, count: 2)

    public private(set) var openTabs: [String] = []
    public private(set) var activeTab: String?
    public private(set) var projectGridLayouts: [String: GridLayout] = [:]
    public private(set) var leftSidebarOpen = true
    public private(set) var rightSidebarOpen = false
    public var isRepoSelectorOpen = false
    public private(set) var closeTabDialog: CloseTabDialogState?
    /// Oturumluk — persist edilmez (spec/21 §12).
    public private(set) var isFocusMode = false
    public private(set) var quitDialogTerminalCount: Int?
    public var isOnboardingActive = false
    public var isSettingsOpen = false
    /// Oturumluk maximize/solo — repo başına en çok bir terminal tam alanı
    /// kaplar; diğer görünürler alt şeride iner. Persist edilmez (spec/21 §12 ruhu).
    public private(set) var maximizedByRepo: [String: TerminalID] = [:]

    /// Quit-onay çözümü app delegate'e köprülenir (.terminateLater akışı).
    @ObservationIgnored public var onQuitResolved: ((Bool) -> Void)?
    /// Traffic-light gizleme AppKit tarafında bu callback ile senkronlanır.
    @ObservationIgnored public var onFocusModeChanged: ((Bool) -> Void)?

    /// Aktif repo değişiminde watch/unwatch + git veri yüklemesi için container
    /// köprüsü (eski değer, yeni değer).
    @ObservationIgnored public var onActiveRepoChanged: ((String?, String?) -> Void)?

    public struct CloseTabDialogState: Equatable {
        public let repoPath: String
        public let repoName: String
        public let minimizedCount: Int
    }

    @ObservationIgnored private let config: any ConfigServicing
    @ObservationIgnored private let terminals: TerminalListStore

    public init(config: any ConfigServicing, terminals: TerminalListStore) {
        self.config = config
        self.terminals = terminals
    }

    /// Bootstrap sözleşmesi (spec/21 §13): repos yüklendikten SONRA çağrılır —
    /// ad→path tab migration'ı ve legacy gridColumns migration'ı repo listesini okur.
    public func load(repos: [Repo]) async {
        let state = await config.uiState()

        var seenTabs = Set<String>()
        openTabs = state.openTabs.compactMap { entry -> String? in
            if repos.contains(where: { $0.path == entry }) {
                return entry
            }
            // Legacy: tab repo ADI olarak yazılmış olabilir
            return repos.first(where: { $0.name == entry })?.path
        }.filter { seenTabs.insert($0).inserted }

        if let storedActive = state.activeTab {
            if openTabs.contains(storedActive) {
                activeTab = storedActive
            } else if let migrated = repos.first(where: { $0.name == storedActive })?.path,
                      openTabs.contains(migrated) {
                activeTab = migrated
            } else {
                activeTab = openTabs.first
            }
        } else {
            activeTab = nil
        }

        projectGridLayouts = state.projectGridLayouts
        if projectGridLayouts.isEmpty, let legacy = state.legacyGridColumns {
            // Legacy global gridColumns → her açık tab'ın path'ine kopyalanır (spec/21 §13)
            for tab in openTabs {
                projectGridLayouts[tab] = legacy
            }
        }
        leftSidebarOpen = state.leftSidebarOpen
        rightSidebarOpen = state.rightSidebarOpen

        if let tab = activeTab {
            terminals.activateRepo(tab)
        }
        onActiveRepoChanged?(nil, activeTab)
    }

    // MARK: - Focus mode / quit dialog (Faz 6)

    public func toggleFocusMode() {
        isFocusMode.toggle()
        onFocusModeChanged?(isFocusMode)
    }

    public func exitFocusMode() {
        guard isFocusMode else { return }
        isFocusMode = false
        onFocusModeChanged?(false)
    }

    public func presentQuitDialog(terminalCount: Int) {
        quitDialogTerminalCount = terminalCount
    }

    public func resolveQuit(_ shouldQuit: Bool) {
        quitDialogTerminalCount = nil
        onQuitResolved?(shouldQuit)
    }

    // MARK: - Sidebar'lar (spec/21 §12: her toggle persist)

    public func toggleLeftSidebar() {
        leftSidebarOpen.toggle()
        persist()
    }

    public func toggleRightSidebar() {
        rightSidebarOpen.toggle()
        persist()
    }

    // MARK: - Tab yönetimi (spec/21 §9)

    public func openTab(_ repoPath: String) {
        if !openTabs.contains(repoPath) {
            openTabs.append(repoPath)
        }
        setActiveTab(repoPath)
    }

    public func setActiveTab(_ repoPath: String) {
        let previous = activeTab
        activeTab = repoPath
        terminals.activateRepo(repoPath) // cross-store yan etki
        persist()
        if previous != repoPath {
            onActiveRepoChanged?(previous, repoPath)
        }
    }

    /// Guard (spec/21 §9): minimize edilmiş terminali olan tab dialog'suz kapanmaz.
    public func requestCloseTab(_ repoPath: String, repoName: String) {
        let minimizedCount = terminals.minimizedTerminals(in: repoPath).count
        if minimizedCount > 0 {
            closeTabDialog = CloseTabDialogState(
                repoPath: repoPath,
                repoName: repoName,
                minimizedCount: minimizedCount
            )
            return
        }
        performCloseTab(repoPath)
    }

    public func confirmCloseTab() {
        guard let dialog = closeTabDialog else { return }
        closeTabDialog = nil
        performCloseTab(dialog.repoPath)
    }

    public func cancelCloseTab() {
        closeTabDialog = nil
    }

    private func performCloseTab(_ repoPath: String) {
        let wasActive = activeTab == repoPath
        openTabs.removeAll { $0 == repoPath }
        if wasActive {
            // Kapanan aktifse listenin SON tab'ı aktif olur (spec/21 §9)
            activeTab = openTabs.last
            if let tab = activeTab {
                terminals.activateRepo(tab)
            } else {
                terminals.focus(nil)
            }
        }
        terminals.closeAll(in: repoPath)
        persist()
        if wasActive {
            onActiveRepoChanged?(repoPath, activeTab)
        } else {
            onActiveRepoChanged?(repoPath, nil) // unwatch için kapanan repo bildirilir
        }
    }

    // MARK: - Grid layout (spec/21 §10)

    public func gridLayout(for repoPath: String?) -> GridLayout {
        guard let repoPath else { return Self.defaultGridLayout }
        return projectGridLayouts[repoPath] ?? Self.defaultGridLayout
    }

    public func setGridLayout(_ layout: GridLayout, for repoPath: String) {
        guard !repoPath.isEmpty else { return }
        projectGridLayouts[repoPath] = layout
        persist() // disk yazımı servis tarafında 500ms debounce'lu
    }

    // MARK: - Maximize / solo (design/03 — tek terminalle çalışma)

    /// Görünür olmayan (kapanmış/minimize) id maximize edilmez; maximize odak da verir.
    public func maximize(_ id: TerminalID, in repoPath: String) {
        guard terminals.visibleTerminals(in: repoPath).contains(where: { $0.id == id }) else { return }
        maximizedByRepo[repoPath] = id
        terminals.focus(id)
    }

    public func toggleMaximize(_ id: TerminalID, in repoPath: String) {
        if maximizedByRepo[repoPath] == id {
            restoreMaximize(in: repoPath)
        } else {
            maximize(id, in: repoPath)
        }
    }

    public func restoreMaximize(in repoPath: String) {
        maximizedByRepo[repoPath] = nil
    }

    /// Aktif maximize hedefi — kart kapanmış/minimize olmuşsa nil döner (görünür
    /// değil); stale dict girdisi okuma sırasında zararsızca yok sayılır.
    public func maximizedTerminal(in repoPath: String) -> TerminalID? {
        guard let id = maximizedByRepo[repoPath],
              terminals.visibleTerminals(in: repoPath).contains(where: { $0.id == id }) else {
            return nil
        }
        return id
    }

    // MARK: - Persistence (spec/21 §13: yalnız bu alt küme)

    private func persist() {
        let tabs = openTabs
        let active = activeTab
        let layouts = projectGridLayouts
        let left = leftSidebarOpen
        let right = rightSidebarOpen
        Task { [config] in
            await config.updateUIState { state in
                state.openTabs = tabs
                state.activeTab = active
                state.projectGridLayouts = layouts
                state.leftSidebarOpen = left
                state.rightSidebarOpen = right
            }
        }
    }
}
