import LumiKit
import SwiftUI

/// Panel görünürlükleri — anında uygulanır ve hatırlanır.
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
                hint: "Sessions · Project Context panel",
                isOn: slotBinding(.left)
            )
            LumiToggleRow(
                title: "Right Sidebar",
                hint: "Git panel (Commits · Changes)",
                isOn: slotBinding(.right)
            )
        }
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
