import Foundation
import LumiKit
import SwiftUI

/// Günlük oturum tetikleyicisi (headless `claude -p`).
struct SessionSettingsTab: SettingsTabContent {
    static let tab: SettingsTab = .session

    @Shell private var shell

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
            LumiSectionTitle(
                title: "Session Trigger",
                description: "Start your Claude usage window automatically at a set time each day."
            )
            InfoCard(
                "When enabled and Lumi is running, a headless \"claude -p\" request with the "
                    + "prompt below is sent at the chosen time to kick off the 5-hour window. "
                    + "It runs in the background and never touches your open terminals."
            )
            LumiToggleRow(
                title: "Daily Trigger",
                hint: "Send the prompt automatically every day",
                isOn: Binding(
                    get: { shell.settings.current.sessionTrigger.enabled },
                    set: { value in updateTrigger { $0.enabled = value } }
                )
            )
            LumiField(title: "Time", hint: "Local time; fires at the next matching time each day") {
                DatePicker("", selection: triggerTimeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .font(Theme.Typography.bodyMono)
                    .frame(width: 140, alignment: .leading)
                    .accessibilityLabel("Daily trigger time")
            }
            LumiField(
                title: "Prompt",
                hint: "Sent to start the session — \"hello\" is enough",
                isLast: true
            ) {
                LumiTextInput(
                    text: Binding(
                        get: { shell.settings.current.sessionTrigger.prompt },
                        set: { value in updateTrigger { $0.prompt = value } }
                    ),
                    placeholder: "hello",
                    width: 260
                )
            }
            statusRow
        }
    }

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if shell.settings.current.sessionTrigger.enabled,
               let next = shell.sessionSchedule.nextFireDate {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "clock")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.accentPrimary)
                        .accessibilityHidden(true)
                    Text("Next trigger")
                        .font(Theme.Typography.bodyMono)
                        .foregroundStyle(Theme.textSecondary)
                    Text(next, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .font(Theme.Typography.mono(.body, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            // 10pt: ölçek dışı ara değer (v1 paritesi korunuyor).
            HStack(spacing: 10) {
                startNowButton
                lastRunLabel
            }
        }
    }

    private var startNowButton: some View {
        Button {
            Task { await shell.sessionSchedule.fireNow() }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                if shell.sessionSchedule.isStarting {
                    ProgressView().controlSize(.small)
                }
                Text(shell.sessionSchedule.isStarting ? "Starting…" : "Start session now")
                    .font(Theme.Typography.mono(.body, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            // 14/7pt: ölçek dışı ara değerler (v1 paritesi korunuyor).
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(shell.sessionSchedule.isStarting)
    }

    @ViewBuilder
    private var lastRunLabel: some View {
        switch shell.sessionSchedule.lastRun {
        case .success(let date):
            statusLine(icon: "checkmark.circle", tint: Theme.accentCyan) {
                Text(date, format: .dateTime.hour().minute())
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textMuted)
            }
        case .failure(let detail, _):
            statusLine(icon: "exclamationmark.triangle", tint: Theme.accentPrimary) {
                Text(detail)
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        case .none:
            EmptyView()
        }
    }

    private func statusLine(
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> some View
    ) -> some View {
        // 5pt: ölçek dışı ara değer (v1 paritesi korunuyor).
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(Theme.Typography.label)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            content()
        }
    }

    private func updateTrigger(_ mutate: @escaping @Sendable (inout SessionTrigger) -> Void) {
        shell.settings.updateSessionTrigger(mutate)
    }

    private var triggerTimeBinding: Binding<Date> {
        Binding(
            get: {
                let trigger = shell.settings.current.sessionTrigger
                return Calendar.current.date(
                    bySettingHour: trigger.hour,
                    minute: trigger.minute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                updateTrigger {
                    $0.hour = components.hour ?? $0.hour
                    $0.minute = components.minute ?? $0.minute
                }
            }
        )
    }
}

#if DEBUG
#Preview("Session") {
    SettingsTabPreview(.session)
}
#endif
