import LumiKit
import SwiftUI

/// Arayüz yazı tipi (karar 63) + panel görünürlükleri + sağ kenarda tek panel
/// kuralı (karar 124) + kenar hover'ıyla açılma (karar 44) — anında uygulanır
/// ve hatırlanır.
struct AppearanceSettingsTab: SettingsTabContent {
    static let tab: SettingsTab = .appearance

    @Shell private var shell

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
            LumiSectionTitle(
                title: "Appearance",
                description: "Interface font and panel visibility. "
                    + "Changes apply instantly and are remembered."
            )
            LumiField(
                title: "Interface Font",
                hint: "System Mono is macOS's own monospace face (SF Mono). "
                    + "JetBrains Mono is the bundled face the Electron build used — "
                    + "larger x-height, tighter shapes, crisper at small sizes. "
                    + "The terminal keeps its own font setting.",
                isLast: true
            ) {
                LumiSegmented(
                    options: UIFontFamily.allCases.map {
                        .init(value: $0, label: $0.displayName)
                    },
                    selection: Binding(
                        get: { shell.layout.uiFontFamily },
                        set: { shell.layout.setUIFontFamily($0) }
                    )
                )
            }
            LumiToggleRow(
                title: "Left Sidebar",
                hint: "Sessions panel",
                isOn: slotBinding(.left)
            )
            LumiToggleRow(
                title: "Right Sidebar",
                hint: "Project Tools (Explorer · Agent History · Source Control)",
                isOn: slotBinding(.right)
            )
            LumiToggleRow(
                title: "Orchestrator Panel",
                hint: "Codex orchestrator between the terminals and the right sidebar (⌘J)",
                isOn: slotBinding(shell.orchestratorPresentation.panelSlot)
            )
            LumiToggleRow(
                title: "One Right Panel at a Time",
                hint: "Opening the orchestrator panel closes the right sidebar, and vice versa",
                isOn: Binding(
                    get: { shell.layout.exclusiveRightPanels },
                    set: { shell.layout.setExclusiveRightPanels($0) }
                )
            )
            LumiToggleRow(
                title: "Auto-reveal Left Sidebar",
                hint: autoRevealHint(.left),
                isOn: autoRevealBinding(.left)
            )
            LumiToggleRow(
                title: "Auto-reveal Right Sidebar",
                hint: autoRevealHint(.right),
                isOn: autoRevealBinding(.right)
            )
        }
    }

    /// Yuva SABİTKEN (docked) auto-reveal'in hiçbir etkisi yoktur
    /// (`LayoutStore.canAutoReveal`) — toggle açık görünüp sessizce hiçbir şey
    /// yapmasın diye sebebi ipucunda söylenir.
    private func autoRevealHint(_ slot: PanelSlot) -> String {
        let edge = slot == .right ? "right" : "left"
        guard !shell.layout.visibleSlots.contains(slot) else {
            return "No effect while the sidebar is pinned — turn it off above to use hover"
        }
        return "Hover the \(edge) edge to show it over the content"
    }

    private func autoRevealBinding(_ slot: PanelSlot) -> Binding<Bool> {
        Binding(
            get: { shell.layout.isAutoReveal(slot) },
            set: { shell.layout.setAutoReveal(slot, $0) }
        )
    }

    private func slotBinding(_ slot: PanelSlot) -> Binding<Bool> {
        Binding(
            get: { shell.layout.visibleSlots.contains(slot) },
            set: { shell.layout.setSlotVisible(slot, $0) }
        )
    }
}

#if DEBUG
#Preview("Appearance") {
    SettingsTabPreview(.appearance)
}
#endif
