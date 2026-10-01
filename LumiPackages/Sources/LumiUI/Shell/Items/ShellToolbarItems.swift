import LumiKit
import SwiftUI

/// Kabuğun KENDİ toolbar öğeleri (Faz 6.4/6.6) — bir feature'a ait olmayanlar:
/// panel yuvası toggle'ları, logo, focus mode ve settings.
///
/// Descriptor'ların **kümesi** composition root'ta kaydedilir
/// (`ShellComposition`); burada üretim fabrikası durur ki "panel toggle'ları
/// `PanelSlot.allCases`'ten türer" kuralı view render etmeden test edilebilsin.
///
/// Karar 55: repo tab şeridi top bar'dan kalktı — projeler ve checkout'lar
/// yalnız sol paneldeki Projects panelinden gezilir.
public enum ShellToolbarItems {
    /// Bölge içi sıralar. Aralıklı numaralar: bir feature araya öğe
    /// sokabilsin diye (yeni öğe = yeni sayı, mevcutlar kaymaz).
    public enum Order {
        public static let logo = 0
        /// Karar 55: sol panel toggle'ı logo + ürün adının ARDINDA durur
        /// (traffic light → logo → toggle).
        public static let panelToggleLeading = 10

        /// Hızlı komutlar (karar 96) — üretim grubunun en solunda, grid ve
        /// birincil CTA'dan önce (Orca'da Run, `+`'nın yanında durur).
        public static let quickCommands = -10
        public static let gridSettings = 0
        public static let newTerminal = 10
        /// Repo-dışı bir route'un kendi başlığı (karar 55) — grid/CTA o
        /// route'ta zaten görünmez, yani sıra çakışmaz.
        public static let routeTitle = 20

        /// Usage göstergeleri en solda: `AgentProvider.allCases` sırasında,
        /// sağlayıcı başına 10 adım.
        public static let usageStep = 10
        /// DeepSeek bakiyesi (karar 75) — sağlayıcı göstergelerinden sonra,
        /// focus mode'dan önce.
        public static let deepSeekBalance = 50
        public static let focusMode = 100
        public static let panelToggleBottom = 105
        public static let panelToggleRight = 110
        public static let settings = 120

        /// Alt bar (karar 43): sol grup settings; sağ grup keep awake → resource manager.
        public static let statusSettings = 0
        public static let keepAwake = 0
        public static let resourceManager = 10
    }

    /// Bir panel yuvasının top bar'daki temsili.
    ///
    /// **Neden tablo?** Toggle'lar `PanelSlot.allCases`'ten türetilir; yuvaya
    /// özel olan yalnız ikon/bölge/sıradır. Yeni bir yuva eklendiğinde tek
    /// satır eklenir, `HeaderBarView` hiç değişmez.
    public struct SlotPresentation: Sendable {
        public let icon: String
        public let region: ToolbarRegion
        public let order: Int
    }

    public static let slotPresentations: [PanelSlot: SlotPresentation] = [
        .left: SlotPresentation(
            icon: "sidebar.left",
            region: .leading,
            order: Order.panelToggleLeading
        ),
        .right: SlotPresentation(
            icon: "sidebar.right",
            region: .trailing,
            order: Order.panelToggleRight
        ),
        .bottom: SlotPresentation(
            icon: "rectangle.bottomthird.inset.filled",
            region: .trailing,
            order: Order.panelToggleBottom
        ),
    ]

    /// Her yuva için bir toggle — **`PanelSlot.allCases`'ten türetilir**.
    ///
    /// Görünürlük kuralı: yuvanın SAHİPLENDİĞİ kayıtlı bir panel öğesi varsa
    /// toggle çizilir. "Sahiplenme" yerleşimden okunur (kullanıcı öğeyi
    /// taşımışsa yeni yuvaya sayılır), yoksa `defaultSlot`'tan. Böylece
    /// bugün kayıtlı öğesi olmayan `.bottom` gizli kalır ve ilk `.bottom`
    /// öğesi kaydedildiği gün kendiliğinden görünür olur. Öğenin `isAvailable`
    /// durumuna BAKILMAZ: hamburger, repo açık değilken de bugünkü gibi durur.
    @MainActor
    public static func panelToggles(panels: PanelItemRegistry) -> [ToolbarItemDescriptor] {
        PanelSlot.allCases.compactMap { slot in
            guard let presentation = slotPresentations[slot] else { return nil }
            return ToolbarItemDescriptor(
                id: .panelToggle(slot),
                region: presentation.region,
                order: presentation.order,
                isVisible: { context in
                    panels.all.contains { item in
                        (context.layout.panelLayout.slot(of: item.id) ?? item.defaultSlot) == slot
                    }
                },
                makeView: { AnyView(PanelToggleToolbarItem(slot: slot, icon: presentation.icon)) }
            )
        }
    }

    /// Kabuğa ait tüm toolbar öğeleri (panel toggle'ları dahil).
    @MainActor
    public static func core(panels: PanelItemRegistry) -> [ToolbarItemDescriptor] {
        panelToggles(panels: panels) + [
            ToolbarItemDescriptor(
                id: .logo,
                region: .leading,
                order: Order.logo,
                makeView: { AnyView(LogoToolbarItem()) }
            ),
            ToolbarItemDescriptor(
                id: .focusMode,
                region: .trailing,
                order: Order.focusMode,
                makeView: { AnyView(FocusModeToolbarItem()) }
            ),
            // Karar 43: settings top bar'dan alt barın soluna taşındı (Orca paritesi).
            ToolbarItemDescriptor(
                id: .settings,
                region: .statusLeading,
                order: Order.statusSettings,
                makeView: { AnyView(SettingsToolbarItem()) }
            ),
        ]
    }
}

// MARK: - Öğe view'ları

/// Bir panel yuvasının görünürlük toggle'ı (eski hamburger + git ikonu).
struct PanelToggleToolbarItem: View {
    let slot: PanelSlot
    let icon: String

    @Shell private var shell

    var body: some View {
        IconButton(
            systemName: icon,
            label: "\(slot.accessibilityName) panel",
            size: .body,
            weight: .regular,
            side: TopBarMetrics.controlHeight,
            role: .toggle,
            isActive: shell.layout.isSlotVisible(slot),
            action: { shell.layout.toggleSlot(slot) }
        )
    }
}

private extension PanelSlot {
    /// Toggle'ın erişilebilirlik adı (ikon tek başına anlamsız).
    var accessibilityName: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .bottom: return "Bottom"
        }
    }
}

/// Logo + ürün adı (ince bar: 18×18 mascot + ad 12/600).
struct LogoToolbarItem: View {
    /// Dev (debug) build'de "dev", release'de "Lumi".
    static let appName: String = {
        #if DEBUG
        return "dev"
        #else
        return "Lumi"
        #endif
    }()

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let logo = LumiAssets.logo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: Theme.Typography.Size.headline.scaledPoints,
                           height: Theme.Typography.Size.headline.scaledPoints)
                    .accessibilityHidden(true)
            }
            Text(Self.appName)
                .font(Theme.Typography.mono(.body, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

/// Focus mode toggle (chrome'u gizler; hover-reveal bar devralır).
struct FocusModeToolbarItem: View {
    @Shell private var shell

    var body: some View {
        IconButton(
            systemName: "arrow.up.left.and.arrow.down.right",
            label: "Focus mode",
            size: .body,
            weight: .regular,
            side: TopBarMetrics.controlHeight,
            role: .toggle,
            isActive: shell.layout.isFocusMode,
            action: { shell.layout.toggleFocusMode() }
        )
    }
}

/// Ayarlar overlay'ini açar (alt bar, sol grup — karar 43).
struct SettingsToolbarItem: View {
    @Shell private var shell

    var body: some View {
        IconButton(
            systemName: "gearshape",
            label: "Settings",
            size: .label,
            weight: .regular,
            side: StatusBarMetrics.controlHeight,
            role: .toggle,
            isActive: shell.dialogs.isSettingsOpen,
            action: { shell.dialogs.isSettingsOpen = true }
        )
    }
}
