import LumiKit
import SwiftUI

/// Ajan bildirimleri (karar 145): tur başına bir bildirim, tekrar yok.
struct NotificationsSettingsTab: SettingsTabContent {
    static let tab: SettingsTab = .notifications

    @Shell private var shell

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
            LumiSectionTitle(
                title: "Notifications",
                description: "One notification per agent turn, with the chat name and the agent's last message."
            )
            InfoCard(
                "System notifications appear only while Lumi is in the background; inside Lumi you get a toast. "
                    + "Nothing is shown for the terminal you are looking at, and idle chats never repeat."
            )
            toggle(
                "Agent finished",
                hint: "When an agent finishes its turn or stops with an error",
                \.agentFinished
            )
            toggle(
                "Needs input",
                hint: "When an agent waits for your permission or answer",
                \.needsInput
            )
            toggle(
                "Sound",
                hint: "Play the system sound with notifications",
                \.sound
            )
        }
    }

    private func toggle(
        _ title: String,
        hint: String,
        _ keyPath: WritableKeyPath<NotificationSettings, Bool> & Sendable
    ) -> some View {
        LumiToggleRow(
            title: title,
            hint: hint,
            isOn: Binding(
                get: { shell.settings.current.notifications[keyPath: keyPath] },
                set: { value in
                    shell.settings.updateNotifications { $0[keyPath: keyPath] = value }
                }
            )
        )
    }
}

#if DEBUG
#Preview("Notifications") {
    SettingsTabPreview(.notifications)
}
#endif
