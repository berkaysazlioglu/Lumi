import Foundation
import LumiKit
import Observation

/// Persist edilen yerleşim alanlarının TEK snapshot'ı (refactor 5.2 / Faz 6.2).
///
/// Alan başına ayrı yazım yerine tek `persist(_:)` girdisi: hangi alanın diske
/// indiği bir yerde okunur. `leftSidebarOpen`/`rightSidebarOpen` artık bağımsız
/// alanlar değil, `panelLayout.visibleSlots`'un PROJEKSİYONudur (K34, karar 9):
/// diske yazılmaya devam ederler ki eski Electron sürümü aynı dosyayı okusun.
public struct LayoutSnapshot: Equatable, Sendable {
    public var panelLayout: PanelLayout
    public var projectGridLayouts: [String: GridLayout]
    /// Karar 61: arayüz ölçeği. %100'de `nil` yazılır — additive anahtar
    /// varsayılan değerde diske hiç girmez (karar 9).
    public var uiScale: Double?
    /// Karar 63: arayüz yazı tipi. `.system`'de `nil` yazılır (uiScale ile aynı
    /// gerekçe).
    public var uiFontFamily: UIFontFamily?
    /// karar 72: sağ panelin seçili sekmesi. Varsayılan sekmede `nil` yazılır.
    public var projectToolsTab: ProjectToolsTab?

    public init(
        panelLayout: PanelLayout,
        projectGridLayouts: [String: GridLayout],
        uiScale: Double? = nil,
        uiFontFamily: UIFontFamily? = nil,
        projectToolsTab: ProjectToolsTab? = nil
    ) {
        self.panelLayout = panelLayout
        self.projectGridLayouts = projectGridLayouts
        self.uiScale = uiScale
        self.uiFontFamily = uiFontFamily
        self.projectToolsTab = projectToolsTab
    }

    /// Karar 9 projeksiyonu — eski bool alanı.
    public var leftSidebarOpen: Bool { panelLayout.isVisible(.left) }
    /// Karar 9 projeksiyonu — eski bool alanı.
    public var rightSidebarOpen: Bool { panelLayout.isVisible(.right) }
}

/// Panel yerleşimi/görünürlüğü, repo başına grid yerleşimi, maximize/solo ve
/// focus mode (refactor 5.2, Faz 6.2; design/03 §4, §7).
///
/// Tek servis bağımlılığı `ConfigServicing`'dir. Maximize'ın "görünür mü?"
/// sorusu terminal store'una SOMUT bağ kurmadan `isTerminalVisible`
/// predikatıyla enjekte edilir — böylece layout, terminal listesinin tipini
/// hiç tanımaz.
///
/// **Panel intent'leri tektir** (Faz 6.2): eski `toggleLeftSidebar` /
/// `toggleRightSidebar` / `setLeftSidebarOpen` / `setRightSidebarOpen` dörtlüsü
/// `toggleSlot(_:)` + `setSlotVisible(_:_:)` ikilisine indi; yeni bir yuva
/// eklendiğinde yeni intent yazılmaz.
@Observable
@MainActor
public final class LayoutStore {
    /// Yeni repo default'u: tek kolon + Fit (karar 31).
    public static let defaultGridLayout = GridLayout(mode: .columns, count: 1, heightMode: .fit)

    /// Hangi öğe hangi yuvada + yuva görünürlükleri + genişlikler (K33/K34).
    public private(set) var panelLayout: PanelLayout = .defaults
    public private(set) var projectGridLayouts: [String: GridLayout] = [:]
    /// Oturumluk maximize/solo — repo başına en çok bir terminal tam alanı
    /// kaplar; diğer görünürler alt şeride iner. Persist edilmez.
    public private(set) var maximizedByRepo: [String: TerminalID] = [:]
    /// Oturumluk — persist edilmez.
    public private(set) var isFocusMode = false
    /// Karar 97: kartların elle sıralandığı Edit modu hangi repo'da açık.
    /// Repo'ya bağlıdır — başka checkout'a geçince o yüzeyde kapalı görünür.
    /// Oturumluk — persist edilmez.
    public private(set) var arrangingRepoPath: String?
    /// Karar 44: kenar hover'ıyla o an içeriğin ÜSTÜNDE açık duran yuvalar.
    /// Oturumluk — persist edilmez; kalıcı tercih `panelLayout.autoRevealSlots`.
    public private(set) var revealedSlots: Set<PanelSlot> = []

    /// Karar 61: arayüz ölçeği (⌘+/⌘−/⌘0). 1.0 = %100.
    public private(set) var uiScale: CGFloat = 1

    /// Karar 63: arayüz yazı tipi (Settings ▸ Appearance). Varsayılan `.system`
    /// = SF Mono, yani karar 63 öncesi davranış.
    public private(set) var uiFontFamily: UIFontFamily = .system

    /// karar 72: sağ panelin (Project Tools) seçili sekmesi. Seçim view'ın
    /// `@State`'indeyken panel her kapanışta — özellikle kenar hover'ıyla
    /// açılan geçici panelde — Explorer'a dönüyordu; yuvanın kendisi gibi
    /// yerleşim durumudur ve `ui-state`'e iner.
    public private(set) var projectToolsTab: ProjectToolsTab = .explorer

    /// Kapalı basamak kümesi — Electron'un çarpansal zoom'u yerine bilinen
    /// değerler: diske yalnız bunlar iner, uçlarda sabitlenir.
    public static let uiScaleSteps: [CGFloat] = [0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]

    /// Traffic-light gizleme AppKit tarafında bu callback ile senkronlanır.
    @ObservationIgnored public var onFocusModeChanged: ((Bool) -> Void)?

    /// Ölçek değişimi: token çarpanını kuran ve arayüzü yeniden kuran köprü
    /// (LumiUI/AppKit tarafı). Store `Theme`'i tanımaz.
    @ObservationIgnored public var onUIScaleChanged: ((CGFloat) -> Void)?

    /// Karar 63: yazı tipi değişimi — `onUIScaleChanged` ile aynı köprü deseni
    /// (token'ı kur + içerik view'ını yeniden kur). Store `Theme`'i tanımaz.
    @ObservationIgnored public var onUIFontFamilyChanged: ((UIFontFamily) -> Void)?

    @ObservationIgnored private let config: any ConfigServicing
    @ObservationIgnored private let isTerminalVisible: (TerminalID, String) -> Bool
    /// Maximize odak da verir. Odaklama terminal store'unun işidir; layout onu
    /// SOMUT olarak tanımasın diye dar bir closure ile enjekte edilir
    /// (`isTerminalVisible` ile aynı gerekçe).
    @ObservationIgnored private let focusTerminal: (TerminalID) -> Void
    /// Persist zincirinin kuyruğu (1.17 — sıra garantisi).
    @ObservationIgnored private var pendingPersistTask: Task<Void, Never>?

    public init(
        config: any ConfigServicing,
        isTerminalVisible: @escaping (TerminalID, String) -> Bool,
        focusTerminal: @escaping (TerminalID) -> Void = { _ in }
    ) {
        self.config = config
        self.isTerminalVisible = isTerminalVisible
        self.focusTerminal = focusTerminal
    }

    // MARK: - Yükleme

    /// `openTabs` yalnız legacy `gridColumns` migration'ı için gerekir: eski
    /// global değer açık her tab'ın path'ine kopyalanır.
    ///
    /// K34 migration: `panelLayout` anahtarı yoksa yerleşim default'tan,
    /// görünürlük eski `leftSidebarOpen`/`rightSidebarOpen` bool'larından gelir.
    public func load(state: UIState, openTabs: [String]) {
        // Bozuk/ara değer en yakın basamağa çekilir — arayüz okunamaz bir
        // ölçekle açılmaz.
        uiScale = Self.nearestScaleStep(state.uiScale.map { CGFloat($0) } ?? 1)
        onUIScaleChanged?(uiScale)
        // Karar 63: anahtar yoksa/bozuksa `.system` — eski davranış.
        uiFontFamily = state.uiFontFamily ?? .system
        onUIFontFamilyChanged?(uiFontFamily)
        // karar 72: anahtar yoksa/bozuksa Explorer.
        projectToolsTab = state.projectToolsTab.flatMap(ProjectToolsTab.init(rawValue:)) ?? .explorer
        projectGridLayouts = state.projectGridLayouts
        if projectGridLayouts.isEmpty, let legacy = state.legacyGridColumns {
            for tab in openTabs {
                projectGridLayouts[tab] = legacy
            }
        }
        panelLayout = state.panelLayout ?? PanelLayout.migrating(
            leftOpen: state.leftSidebarOpen,
            rightOpen: state.rightSidebarOpen
        )

        // Karar 55: sessions → tasks dönüşümü SIRA migration'ından ÖNCE koşar
        // (sıra kuralı Tasks'ı çapa alır).
        let migratedTasks = panelLayout.migratingSessionsToTasks()
        if migratedTasks != panelLayout {
            panelLayout = migratedTasks
            persist()
        }

        let migratedOrder = panelLayout.migratingProjectsAfterTasks()
        if migratedOrder != panelLayout {
            panelLayout = migratedOrder
            persist()
        }
        if panelLayout.slot(of: .projects) == nil {
            let insertionIndex = panelLayout.items(in: .left).firstIndex(of: .tasks).map { $0 + 1 } ?? 0
            panelLayout = panelLayout.moving(.projects, to: .left, index: insertionIndex)
            persist()
        }
    }

    // MARK: - Focus mode

    public func toggleFocusMode() {
        isFocusMode.toggle()
        revealedSlots = []
        onFocusModeChanged?(isFocusMode)
    }

    public func exitFocusMode() {
        guard isFocusMode else { return }
        isFocusMode = false
        onFocusModeChanged?(false)
    }

    // MARK: - Panel yuvaları (her mutasyon persist)

    /// Kalıcı görünürlük — focus mode'un GEÇİCİ override'ını içermez.
    public var visibleSlots: Set<PanelSlot> { panelLayout.visibleSlots }

    /// Kabuğun çizim kararı: focus mode açıkken hiçbir yuva görünmez ama
    /// `visibleSlots` (dolayısıyla disk) değişmez — çıkışta eski hal geri gelir.
    public func isSlotVisible(_ slot: PanelSlot) -> Bool {
        !isFocusMode && panelLayout.isVisible(slot)
    }

    public func items(in slot: PanelSlot) -> [PanelItemID] {
        panelLayout.items(in: slot)
    }

    public func width(for slot: PanelSlot) -> Double {
        panelLayout.width(for: slot)
    }

    public func toggleSlot(_ slot: PanelSlot) {
        apply(panelLayout.togglingVisible(slot))
    }

    /// Idempotent (Settings → Appearance toggle'ları): değişmezse yazım yok.
    public func setSlotVisible(_ slot: PanelSlot, _ visible: Bool) {
        apply(panelLayout.settingVisible(slot, visible))
    }

    /// **Bir öğeyi soldan sağa taşımak: TEK mutasyon.**
    public func move(item: PanelItemID, to slot: PanelSlot, index: Int? = nil) {
        apply(panelLayout.moving(item, to: slot, index: index))
    }

    public func setWidth(_ width: Double, for slot: PanelSlot) {
        apply(panelLayout.settingWidth(width, for: slot))
    }

    private func apply(_ newLayout: PanelLayout) {
        guard newLayout != panelLayout else { return }
        panelLayout = newLayout
        // Sabitlenen ya da tercihi kapanan yuvanın geçici overlay'i düşer.
        revealedSlots = revealedSlots.filter { canAutoReveal($0) }
        persist()
    }

    // MARK: - Auto-reveal (karar 44)

    /// Kalıcı tercih: yuva gizliyken kenar hover'ı onu içeriğin üstünde açar.
    public func isAutoReveal(_ slot: PanelSlot) -> Bool {
        panelLayout.isAutoReveal(slot)
    }

    /// Idempotent (Settings → Appearance toggle'ları).
    public func setAutoReveal(_ slot: PanelSlot, _ enabled: Bool) {
        apply(panelLayout.settingAutoReveal(slot, enabled))
    }

    /// Kenar hover bölgesi bu yuva için çizilir mi: tercih açık + yuva sabit
    /// değil (gizli) + focus mode kapalı. Sabit (docked) yuvada overlay
    /// anlamsızdır — zaten görünür.
    public func canAutoReveal(_ slot: PanelSlot) -> Bool {
        !isFocusMode && panelLayout.isAutoReveal(slot) && !panelLayout.isVisible(slot)
    }

    /// Kabuğun çizim kararı: yuva o an overlay olarak açık mı.
    public func isSlotRevealed(_ slot: PanelSlot) -> Bool {
        canAutoReveal(slot) && revealedSlots.contains(slot)
    }

    /// Hover zamanlayıcıları (view) buraya iner; uygun olmayan yuva açılmaz.
    public func setRevealed(_ slot: PanelSlot, _ revealed: Bool) {
        if revealed {
            guard canAutoReveal(slot) else { return }
            revealedSlots.insert(slot)
        } else {
            revealedSlots.remove(slot)
        }
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

    /// Görünür olmayan (kapanmış/minimize) id maximize edilmez. Başarılıysa
    /// odak da verilir (enjekte edilen `focusTerminal` üzerinden) — layout
    /// terminal listesinin tipini yine tanımaz.
    @discardableResult
    public func maximize(_ id: TerminalID, in repoPath: String) -> Bool {
        guard isTerminalVisible(id, repoPath) else { return false }
        maximizedByRepo[repoPath] = id
        focusTerminal(id)
        return true
    }

    /// Aynı id ikinci kez → restore (menü Cmd+Ctrl+M ve kart butonu aynı intent).
    public func toggleMaximize(_ id: TerminalID, in repoPath: String) {
        if isMaximized(id, in: repoPath) {
            restoreMaximize(in: repoPath)
        } else {
            maximize(id, in: repoPath)
        }
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

    // MARK: - Elle sıralama (karar 97)

    public func isArranging(in repoPath: String) -> Bool {
        arrangingRepoPath == repoPath
    }

    /// Edit modu grid üzerinde çalışır: açılırken maximize/solo bırakılır.
    public func toggleArranging(in repoPath: String) {
        if isArranging(in: repoPath) {
            endArranging()
        } else {
            restoreMaximize(in: repoPath)
            arrangingRepoPath = repoPath
        }
    }

    public func endArranging() {
        arrangingRepoPath = nil
    }

    // MARK: - Cache eviction (refactor 5.5)

    /// Tab kapanınca oturumluk maximize kaydı düşer. `projectGridLayouts`
    /// KASITLI olarak korunur: persist edilen bir kullanıcı tercihidir
    /// (karar 9) — tab yeniden açıldığında yerleşimi geri gelmelidir.
    public func evict(_ repoPath: String) {
        maximizedByRepo.removeValue(forKey: repoPath)
        if arrangingRepoPath == repoPath { endArranging() }
    }

    // MARK: - Persistence

    public var snapshot: LayoutSnapshot {
        LayoutSnapshot(
            panelLayout: panelLayout,
            projectGridLayouts: projectGridLayouts,
            // %100 varsayılanında nil: additive anahtar dosyada görünmez.
            uiScale: uiScale == 1 ? nil : Double(uiScale),
            // `.system` varsayılanında nil: aynı gerekçe.
            uiFontFamily: uiFontFamily == .system ? nil : uiFontFamily,
            // Explorer varsayılanında nil: aynı gerekçe.
            projectToolsTab: projectToolsTab == .explorer ? nil : projectToolsTab
        )
    }

    // MARK: - Sağ panel sekmesi (karar 72)

    /// Idempotent; yalnız değişimde diske iner.
    public func setProjectToolsTab(_ tab: ProjectToolsTab) {
        guard tab != projectToolsTab else { return }
        projectToolsTab = tab
        persist()
    }

    // MARK: - Arayüz ölçeği (karar 61)

    public func zoomIn() { stepZoom(by: 1) }
    public func zoomOut() { stepZoom(by: -1) }
    public func resetZoom() { applyScale(1) }

    private func stepZoom(by offset: Int) {
        let steps = Self.uiScaleSteps
        let current = steps.firstIndex(of: uiScale) ?? steps.firstIndex(of: 1) ?? 0
        let target = min(max(current + offset, 0), steps.count - 1)
        applyScale(steps[target])
    }

    // MARK: - Arayüz yazı tipi (karar 63)

    public func setUIFontFamily(_ family: UIFontFamily) {
        guard family != uiFontFamily else { return }
        uiFontFamily = family
        onUIFontFamilyChanged?(family)
        persist()
    }

    private func applyScale(_ scale: CGFloat) {
        guard scale != uiScale else { return }
        uiScale = scale
        onUIScaleChanged?(scale)
        persist()
    }

    /// Diskten gelen değeri kapalı kümeye çeker.
    static func nearestScaleStep(_ value: CGFloat) -> CGFloat {
        guard value.isFinite, value > 0 else { return 1 }
        return uiScaleSteps.min { abs($0 - value) < abs($1 - value) } ?? 1
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
                // Karar 9: eski bool alanları `visibleSlots`'un projeksiyonu
                // olarak YAZILMAYA devam eder.
                state.leftSidebarOpen = snapshot.leftSidebarOpen
                state.rightSidebarOpen = snapshot.rightSidebarOpen
                state.panelLayout = snapshot.panelLayout
                state.projectGridLayouts = snapshot.projectGridLayouts
                state.uiScale = snapshot.uiScale
                state.uiFontFamily = snapshot.uiFontFamily
                state.projectToolsTab = snapshot.projectToolsTab?.rawValue
            }
        }
    }
}
