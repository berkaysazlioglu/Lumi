import LumiKit
import SwiftUI

/// Panel görünürlükleri + kenar hover'ıyla açılma (karar 44) — anında
/// uygulanır ve hatırlanır.
struct AppearanceSettingsTab: SettingsTabContent {
    static let tab: SettingsTab = .appearance

    @Shell private var shell

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
            LumiSectionTitle(
                title: "Appearance",
                description: "Panel visibility. Changes apply instantly and are remembered."
            )
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
                title: "Auto-reveal Left Sidebar",
                hint: "When hidden, hover the left edge to show it over the content",
                isOn: autoRevealBinding(.left)
            )
            LumiToggleRow(
                title: "Auto-reveal Right Sidebar",
                hint: "When hidden, hover the right edge to show it over the content",
                isOn: autoRevealBinding(.right)
            )
        }
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
