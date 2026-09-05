import LumiKit
import SwiftUI

/// Kabuğun KENDİ toolbar öğeleri (Faz 6.4/6.6) — bir feature'a ait olmayanlar:
/// panel yuvası toggle'ları, logo, repo tab şeridi, focus mode ve settings.
///
/// Descriptor'ların **kümesi** composition root'ta kaydedilir
/// (`ShellComposition`); burada üretim fabrikası durur ki "panel toggle'ları
/// `PanelSlot.allCases`'ten türer" kuralı view render etmeden test edilebilsin.
public enum ShellToolbarItems {
    /// Bölge içi sıralar. Aralıklı numaralar: bir feature araya öğe
    /// sokabilsin diye (yeni öğe = yeni sayı, mevcutlar kaymaz).
    public enum Order {
        public static let panelToggleLeading = 0
        public static let logo = 10
        public static let repoTabs = 20

        public static let gridSettings = 0
        public static let newTerminal = 10

        /// Usage göstergeleri en solda: `AgentProvider.allCases` sırasında,
        /// sağlayıcı başına 10 adım.
        public static let usageStep = 10
        public static let focusMode = 100
        public static let panelToggleBottom = 105
        public static let panelToggleRight = 110
        public static let settings = 120
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
            icon: "line.3.horizontal",
            region: .leading,
            order: Order.panelToggleLeading
        ),
        .right: SlotPresentation(
            icon: "arrow.triangle.branch",
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
                id: .repoTabs,
                region: .leading,
                order: Order.repoTabs,
                makeView: { AnyView(RepoTabStrip()) }
            ),
            ToolbarItemDescriptor(
                id: .focusMode,
                region: .trailing,
                order: Order.focusMode,
                makeView: { AnyView(FocusModeToolbarItem()) }
            ),
            ToolbarItemDescriptor(
                id: .settings,
                region: .trailing,
                order: Order.settings,
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
        HeaderIconButton(
            icon: icon,
            isActive: shell.layout.isSlotVisible(slot),
            action: { shell.layout.toggleSlot(slot) }
        )
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
        HStack(spacing: 6) {
            if let logo = LumiAssets.logo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
            }
            Text(Self.appName)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

/// Focus mode toggle (chrome'u gizler; hover-reveal bar devralır).
struct FocusModeToolbarItem: View {
    @Shell private var shell

    var body: some View {
        HeaderIconButton(
            icon: "arrow.up.left.and.arrow.down.right",
            isActive: shell.layout.isFocusMode,
            action: { shell.layout.toggleFocusMode() }
        )
    }
}

/// Ayarlar overlay'ini açar.
struct SettingsToolbarItem: View {
    @Shell private var shell

    var body: some View {
        HeaderIconButton(
            icon: "gearshape",
            isActive: shell.dialogs.isSettingsOpen,
            action: { shell.dialogs.isSettingsOpen = true }
        )
    }
}
