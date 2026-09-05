import LumiKit
import SwiftUI

/// Bekleyen terminaller için tekrar bildirim aralıkları.
struct NotificationsSettingsTab: SettingsTabContent {
    static let tab: SettingsTab = .notifications

    @Shell private var shell

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
            LumiSectionTitle(
                title: "Notifications",
                description: "Repeat notification intervals while the assistant waits for input."
            )
            InfoCard(
                "Notifications only appear when system permission is granted. The interval "
                    + "repeats as long as the terminal stays waiting."
            )
            LumiToggleRow(
                title: "Waiting (unseen)",
                hint: "Instant notification + repeat for unseen waiting terminals",
                isOn: Binding(
                    get: { shell.settings.current.notifications.unseenEnabled },
                    set: { value in
                        shell.settings.updateNotifications { $0.unseenEnabled = value }
                    }
                )
            ) {
                IntervalStepper(
                    label: "Unseen repeat interval",
                    value: Binding(
                        get: { shell.settings.current.notifications.unseenIntervalMinutes },
                        set: { minutes in
                            shell.settings.updateNotifications { $0.unseenIntervalMinutes = minutes }
                        }
                    )
                )
            }
            LumiToggleRow(
                title: "Waiting (seen)",
                hint: "Repeat for seen but unanswered terminals",
                isOn: Binding(
                    get: { shell.settings.current.notifications.seenEnabled },
                    set: { value in
                        shell.settings.updateNotifications { $0.seenEnabled = value }
                    }
                )
            ) {
                IntervalStepper(
                    label: "Seen repeat interval",
                    value: Binding(
                        get: { shell.settings.current.notifications.seenIntervalMinutes },
                        set: { minutes in
                            shell.settings.updateNotifications { $0.seenIntervalMinutes = minutes }
                        }
                    )
                )
            }
        }
    }
}

/// Dakika cinsinden aralık seçici (1–60).
struct IntervalStepper: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Stepper("\(value)", value: $value, in: 1...60)
                .font(Theme.Typography.bodyMono)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 110, alignment: .leading)
                .accessibilityLabel(label)
            Text("min")
                .font(Theme.Typography.bodyMono)
                .foregroundStyle(Theme.textMuted)
        }
    }
}

#if DEBUG
#Preview("Notifications") {
    SettingsTabPreview(.notifications)
}
#endif
