import Foundation
import LumiKit
import Observation

/// Persist edilen yerleşim alanlarının TEK snapshot'ı (refactor 5.2).
///
/// Alan başına ayrı yazım yerine tek `persist(_:)` girdisi: hangi alanın
/// diske indiği bir yerde okunur ve Faz 6'da `visibleSlots`/`panelLayout`
/// eklendiğinde tek yer değişir.
public struct LayoutSnapshot: Equatable, Sendable {
    public var leftSidebarOpen: Bool
    public var rightSidebarOpen: Bool
    public var projectGridLayouts: [String: GridLayout]

    public init(
        leftSidebarOpen: Bool,
        rightSidebarOpen: Bool,
        projectGridLayouts: [String: GridLayout]
    ) {
        self.leftSidebarOpen = leftSidebarOpen
        self.rightSidebarOpen = rightSidebarOpen
        self.projectGridLayouts = projectGridLayouts
    }
}

/// Panel görünürlüğü, repo başına grid yerleşimi, maximize/solo ve focus mode
/// (refactor 5.2; design/03 §4).
///
/// Tek servis bağımlılığı `ConfigServicing`'dir. Maximize'ın "görünür mü?"
/// sorusu terminal store'una SOMUT bağ kurmadan `isTerminalVisible`
/// predikatıyla enjekte edilir — böylece layout, terminal listesinin tipini
/// hiç tanımaz.
@Observable
@MainActor
public final class LayoutStore {
    /// Yeni repo default'u: tek kolon + Fit (karar 31).
    public static let defaultGridLayout = GridLayout(mode: .columns, count: 1, heightMode: .fit)

    public private(set) var leftSidebarOpen = true
    public private(set) var rightSidebarOpen = false
    public private(set) var projectGridLayouts: [String: GridLayout] = [:]
    /// Oturumluk maximize/solo — repo başına en çok bir terminal tam alanı
    /// kaplar; diğer görünürler alt şeride iner. Persist edilmez.
    public private(set) var maximizedByRepo: [String: TerminalID] = [:]
    /// Oturumluk — persist edilmez.
    public private(set) var isFocusMode = false

    /// Traffic-light gizleme AppKit tarafında bu callback ile senkronlanır.
    @ObservationIgnored public var onFocusModeChanged: ((Bool) -> Void)?

    @ObservationIgnored private let config: any ConfigServicing
    @ObservationIgnored private let isTerminalVisible: (TerminalID, String) -> Bool
    /// Persist zincirinin kuyruğu (1.17 — sıra garantisi).
    @ObservationIgnored private var pendingPersistTask: Task<Void, Never>?

    public init(
        config: any ConfigServicing,
        isTerminalVisible: @escaping (TerminalID, String) -> Bool
    ) {
        self.config = config
        self.isTerminalVisible = isTerminalVisible
    }

    // MARK: - Yükleme

    /// `openTabs` yalnız legacy `gridColumns` migration'ı için gerekir: eski
    /// global değer açık her tab'ın path'ine kopyalanır.
    public func load(state: UIState, openTabs: [String]) {
        projectGridLayouts = state.projectGridLayouts
        if projectGridLayouts.isEmpty, let legacy = state.legacyGridColumns {
            for tab in openTabs {
                projectGridLayouts[tab] = legacy
            }
        }
        leftSidebarOpen = state.leftSidebarOpen
        rightSidebarOpen = state.rightSidebarOpen
    }

    // MARK: - Focus mode

    public func toggleFocusMode() {
        isFocusMode.toggle()
        onFocusModeChanged?(isFocusMode)
    }

    public func exitFocusMode() {
        guard isFocusMode else { return }
        isFocusMode = false
        onFocusModeChanged?(false)
    }

    // MARK: - Sidebar'lar (her toggle persist)

    public func toggleLeftSidebar() {
        leftSidebarOpen.toggle()
        persist()
    }

    public func toggleRightSidebar() {
        rightSidebarOpen.toggle()
        persist()
    }

    /// Settings → Appearance toggle'ları için doğrudan set (idempotent; persist).
    public func setLeftSidebarOpen(_ open: Bool) {
        guard leftSidebarOpen != open else { return }
        leftSidebarOpen = open
        persist()
    }

    public func setRightSidebarOpen(_ open: Bool) {
        guard rightSidebarOpen != open else { return }
        rightSidebarOpen = open
        persist()
    }

    // MARK: - Grid layout

    public func gridLayout(for repoPath: String?) -> GridLayout {
        guard let repoPath else { return Self.defaultGridLayout }
        return projectGridLayouts[repoPath] ?? Self.defaultGridLayout
    }

    public func setGridLayout(_ layout: GridLayout, for repoPath: String) {
        guard !repoPath.isEmpty else { return }
        projectGridLayouts[repoPath] = layout
        persist() // disk yazımı servis tarafında 500ms debounce'lu
    }

    // MARK: - Maximize / solo

    /// Görünür olmayan (kapanmış/minimize) id maximize edilmez.
    /// Odak verme çağıranın işidir (facade `TerminalFocusCoordinating`'e delege
    /// eder) — layout terminal listesini tanımaz.
    @discardableResult
    public func maximize(_ id: TerminalID, in repoPath: String) -> Bool {
        guard isTerminalVisible(id, repoPath) else { return false }
        maximizedByRepo[repoPath] = id
        return true
    }

    public func restoreMaximize(in repoPath: String) {
        maximizedByRepo[repoPath] = nil
    }

    public func isMaximized(_ id: TerminalID, in repoPath: String) -> Bool {
        maximizedByRepo[repoPath] == id
    }

    /// Aktif maximize hedefi — kart kapanmış/minimize olmuşsa nil döner
    /// (görünür değil); stale dict girdisi okuma sırasında zararsızca yok sayılır.
    public func maximizedTerminal(in repoPath: String) -> TerminalID? {
        guard let id = maximizedByRepo[repoPath], isTerminalVisible(id, repoPath) else {
            return nil
        }
        return id
    }

    // MARK: - Cache eviction (refactor 5.5)

    /// Tab kapanınca oturumluk maximize kaydı düşer. `projectGridLayouts`
    /// KASITLI olarak korunur: persist edilen bir kullanıcı tercihidir
    /// (karar 9) — tab yeniden açıldığında yerleşimi geri gelmelidir.
    public func evict(_ repoPath: String) {
        maximizedByRepo.removeValue(forKey: repoPath)
    }

    // MARK: - Persistence

    public var snapshot: LayoutSnapshot {
        LayoutSnapshot(
            leftSidebarOpen: leftSidebarOpen,
            rightSidebarOpen: rightSidebarOpen,
            projectGridLayouts: projectGridLayouts
        )
    }

    /// Yazımlar tek zincirde serileştirilir (1.17): geç kalan BAYAT snapshot en
    /// son diske inmesin.
    private func persist() {
        persist(snapshot)
    }

    private func persist(_ snapshot: LayoutSnapshot) {
        let previous = pendingPersistTask
        pendingPersistTask = Task { [config] in
            await previous?.value
            await config.updateUIState { state in
                state.leftSidebarOpen = snapshot.leftSidebarOpen
                state.rightSidebarOpen = snapshot.rightSidebarOpen
                state.projectGridLayouts = snapshot.projectGridLayouts
            }
        }
    }
}
