import Foundation
import LumiKit
import LumiState
import SwiftUI

/// Settings modal'ı (v1 SettingsModal paritesi; spec/22 §5). Sol dikey ikonlu
/// navigasyon + sağ scroll'lu içerik; 700×600. Beş sekme: General, Terminal,
/// Appearance, Notifications, Shortcuts.
///
/// Kaydetme modeli: macOS anlık uygulama (karar 3) — v1'deki Save/Cancel footer'ı
/// YOK, her değişiklik anında yazılır ve yan etkisi koordinatörden akar.
struct SettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case general = "General"
        case terminal = "Terminal"
        case appearance = "Appearance"
        case notifications = "Notifications"
        case session = "Session"
        case usage = "Usage"
        case shortcuts = "Shortcuts"

        var id: String { rawValue }

        /// v1 lucide ikonlarının SF Symbol karşılığı.
        var icon: String {
            switch self {
            case .general: return "folder"
            case .terminal: return "terminal"
            case .appearance: return "paintpalette"
            case .notifications: return "bell"
            case .session: return "clock.arrow.circlepath"
            case .usage: return "gauge.with.dots.needle.bottom.50percent"
            case .shortcuts: return "keyboard"
            }
        }
    }

    let settings: SettingsStore
    let workspace: WorkspaceStore
    let sessionSchedule: SessionScheduleStore
    let usage: UsageStore
    let chooseFolder: () async -> String?
    let onClose: () -> Void

    @State private var selectedTab: Tab = .general

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
            panel
                .frame(width: 700, height: 600)
        }
        .onExitCommand(perform: onClose)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 0) {
                navigation
                    .frame(width: 180)
                Rectangle().fill(Theme.border).frame(width: 1)
                ScrollView {
                    content
                        .padding(.horizontal, 32)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 32, y: 16)
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            SettingsCloseButton(action: onClose)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Tab.allCases) { tab in
                SettingsNavItem(
                    icon: tab.icon,
                    label: tab.rawValue,
                    isActive: selectedTab == tab
                ) {
                    selectedTab = tab
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .general: generalTab
        case .terminal: terminalTab
        case .appearance: appearanceTab
        case .notifications: notificationsTab
        case .session: sessionTab
        case .usage: usageTab
        case .shortcuts: shortcutsTab
        }
    }

    // MARK: - General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionTitle(
                title: "General",
                description: "Repo discovery and default AI provider."
            )
            SettingsField(
                title: "Projects Root",
                hint: "First-level subdirectories are listed as repos"
            ) {
                HStack(spacing: 8) {
                    Text(settings.current.projectsRoot.isEmpty
                        ? "(not set)" : settings.current.projectsRoot)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.bgDeep)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    SettingsBrowseButton(icon: "folder", label: "Browse") {
                        Task { @MainActor in
                            if let path = await chooseFolder() {
                                settings.setProjectsRoot(path)
                            }
                        }
                    }
                }
            }
            SettingsField(
                title: "Additional Paths",
                hint: "root: subdirectories are scanned · repo: added on its own"
            ) {
                additionalPathsField
            }
            SettingsField(
                title: "AI Provider",
                hint: "CLI used for new terminals and actions",
                isLast: true
            ) {
                SettingsSegmented(
                    options: [
                        .init(value: AgentProvider.claude, label: "Claude"),
                        .init(value: AgentProvider.codex, label: "Codex"),
                    ],
                    selection: Binding(
                        get: { settings.current.aiProvider },
                        set: { settings.setProvider($0) }
                    )
                )
            }
        }
    }

    private var additionalPathsField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SettingsBrowseButton(icon: "folder", label: "Add Root Directory") {
                    addPath(type: .root)
                }
                SettingsBrowseButton(icon: "folder.badge.gearshape", label: "Add Repository") {
                    addPath(type: .repo)
                }
            }
            if !settings.current.additionalPaths.isEmpty {
                VStack(spacing: 4) {
                    ForEach(settings.current.additionalPaths) { entry in
                        additionalPathRow(entry)
                    }
                }
            }
        }
    }

    private func additionalPathRow(_ entry: AdditionalPath) -> some View {
        let isRoot = entry.type == .root
        return HStack(spacing: 8) {
            Text(entry.type.rawValue.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(isRoot ? Theme.accentPrimary : Theme.accentCyan)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background((isRoot ? Theme.accentPrimary : Theme.accentCyan).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(entry.path)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button {
                settings.removeAdditionalPath(id: entry.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minHeight: 32)
        .background(Theme.bgDeep)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func addPath(type: AdditionalPath.PathType) {
        Task { @MainActor in
            if let path = await chooseFolder() {
                settings.addAdditionalPath(path, type: type)
            }
        }
    }

    // MARK: - Terminal

    private var terminalTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionTitle(
                title: "Terminal",
                description: "Limit, color theme, font, and cursor. Changes apply instantly."
            )
            SettingsField(
                title: "Max Terminals",
                hint: "1–20; the limit only affects new spawns"
            ) {
                Stepper(
                    "\(settings.current.maxTerminals)",
                    value: Binding(
                        get: { settings.current.maxTerminals },
                        set: { settings.setMaxTerminals($0) }
                    ),
                    in: 1...20
                )
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 140, alignment: .leading)
            }
            SettingsField(
                title: "Color Theme",
                hint: "Applies to all open terminals instantly"
            ) {
                themePicker
            }
            SettingsField(
                title: "Font Family",
                hint: "Monospace fonts installed on this Mac"
            ) {
                fontFamilyPicker
            }
            SettingsField(
                title: "Font Size",
                hint: "10–24px; applies to all open terminals instantly"
            ) {
                Stepper(
                    "\(settings.current.terminalFontSize) px",
                    value: Binding(
                        get: { settings.current.terminalFontSize },
                        set: { settings.setTerminalFontSize($0) }
                    ),
                    in: 10...24
                )
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 140, alignment: .leading)
            }
            SettingsField(
                title: "Cursor",
                hint: "Caret shape and blinking"
            ) {
                cursorControls
            }
            SettingsField(
                title: "Font Smoothing",
                hint: "macOS stem darkening — bolder strokes when on. "
                    + "Off matches the thinner v1 look. Applies instantly.",
                isLast: true
            ) {
                Toggle("", isOn: Binding(
                    get: { settings.current.terminalFontSmoothing },
                    set: { settings.setTerminalFontSmoothing($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(Theme.accentPrimary)
            }
        }
    }

    private var themePicker: some View {
        VStack(spacing: 4) {
            ForEach(TerminalThemeCatalog.all) { option in
                themeRow(option)
            }
        }
    }

    private func themeRow(_ option: TerminalThemeOption) -> some View {
        let isActive = settings.current.terminalTheme == option.id
        return Button {
            settings.setTerminalTheme(option.id)
        } label: {
            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    ForEach(Array(option.previewHex.enumerated()), id: \.offset) { _, hex in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: hex))
                            .frame(width: 12, height: 16)
                    }
                }
                Text(option.name)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(isActive ? Theme.accentPrimary : Theme.textPrimary)
                Spacer(minLength: 0)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.accentPrimary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isActive ? Theme.accentVivid.opacity(0.1) : Theme.bgDeep)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? Theme.accentVivid : Theme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var fontFamilyPicker: some View {
        Picker(
            "",
            selection: Binding(
                get: { settings.current.terminalFontFamily },
                set: { settings.setTerminalFontFamily($0) }
            )
        ) {
            Text("JetBrains Mono (Default)").tag("")
            Divider()
            ForEach(LumiFonts.availableMonospaceFamilies, id: \.self) { family in
                Text(family).tag(family)
            }
        }
        .labelsHidden()
        .font(.system(size: 12, design: .monospaced))
        .frame(width: 260, alignment: .leading)
    }

    private var cursorControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSegmented(
                options: TerminalCursorShape.allCases.map {
                    .init(value: $0, label: $0.label)
                },
                selection: Binding(
                    get: { TerminalCursorShape.parse(settings.current.terminalCursorStyle) },
                    set: { settings.setTerminalCursorStyle($0) }
                )
            )
            HStack(spacing: 10) {
                Text("Blink")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                SettingsToggleSwitch(isOn: Binding(
                    get: { settings.current.terminalCursorBlink },
                    set: { settings.setTerminalCursorBlink($0) }
                ))
            }
        }
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionTitle(
                title: "Appearance",
                description: "Panel visibility. Changes apply instantly and are remembered."
            )
            SettingsToggleRow(
                title: "Left Sidebar",
                hint: "Sessions · Project Context · Quick Actions panel",
                isOn: Binding(
                    get: { workspace.leftSidebarOpen },
                    set: { workspace.setLeftSidebarOpen($0) }
                )
            )
            SettingsToggleRow(
                title: "Right Sidebar",
                hint: "Git panel (Commits · Changes)",
                isOn: Binding(
                    get: { workspace.rightSidebarOpen },
                    set: { workspace.setRightSidebarOpen($0) }
                )
            )
        }
    }

    // MARK: - Notifications

    private var notificationsTab: some View {
        let current = settings.current.notifications
        return VStack(alignment: .leading, spacing: 24) {
            SettingsSectionTitle(
                title: "Notifications",
                description: "Repeat notification intervals while the assistant waits for input."
            )
            infoCard("Notifications only appear when system permission is granted. The interval "
                + "repeats as long as the terminal stays waiting.")
            SettingsToggleRow(
                title: "Waiting (unseen)",
                hint: "Instant notification + repeat for unseen waiting terminals",
                isOn: Binding(
                    get: { settings.current.notifications.unseenEnabled },
                    set: { value in
                        var updated = current
                        updated.unseenEnabled = value
                        settings.setNotifications(updated)
                    }
                )
            ) {
                intervalStepper(Binding(
                    get: { current.unseenIntervalMinutes },
                    set: { minutes in
                        var updated = current
                        updated.unseenIntervalMinutes = minutes
                        settings.setNotifications(updated)
                    }
                ))
            }
            SettingsToggleRow(
                title: "Waiting (seen)",
                hint: "Repeat for seen but unanswered terminals",
                isOn: Binding(
                    get: { settings.current.notifications.seenEnabled },
                    set: { value in
                        var updated = current
                        updated.seenEnabled = value
                        settings.setNotifications(updated)
                    }
                )
            ) {
                intervalStepper(Binding(
                    get: { current.seenIntervalMinutes },
                    set: { minutes in
                        var updated = current
                        updated.seenIntervalMinutes = minutes
                        settings.setNotifications(updated)
                    }
                ))
            }
        }
    }

    private func infoCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(Theme.accentPrimary)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentVivid.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.accentVivid.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func intervalStepper(_ value: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Stepper("\(value.wrappedValue)", value: value, in: 1...60)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 110, alignment: .leading)
            Text("min")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        }
    }

    // MARK: - Session

    private var sessionTab: some View {
        let trigger = settings.current.sessionTrigger
        return VStack(alignment: .leading, spacing: 24) {
            SettingsSectionTitle(
                title: "Session Trigger",
                description: "Start your Claude usage window automatically at a set time each day."
            )
            infoCard("When enabled and Lumi is running, a headless \"claude -p\" request with the "
                + "prompt below is sent at the chosen time to kick off the 5-hour window. It runs "
                + "in the background and never touches your open terminals.")
            SettingsToggleRow(
                title: "Daily Trigger",
                hint: "Send the prompt automatically every day",
                isOn: Binding(
                    get: { settings.current.sessionTrigger.enabled },
                    set: { value in updateTrigger { $0.enabled = value } }
                )
            )
            SettingsField(
                title: "Time",
                hint: "Local time; fires at the next matching time each day"
            ) {
                DatePicker("", selection: triggerTimeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 140, alignment: .leading)
            }
            SettingsField(
                title: "Prompt",
                hint: "Sent to start the session — \"hello\" is enough",
                isLast: true
            ) {
                TextField("hello", text: Binding(
                    get: { settings.current.sessionTrigger.prompt },
                    set: { value in updateTrigger { $0.prompt = value } }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 260, alignment: .leading)
            }
            sessionStatusRow(trigger)
        }
    }

    private func sessionStatusRow(_ trigger: SessionTrigger) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if trigger.enabled, let next = sessionSchedule.nextFireDate {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accentPrimary)
                    Text("Next trigger")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                    Text(next, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            HStack(spacing: 10) {
                Button {
                    Task { await sessionSchedule.fireNow() }
                } label: {
                    HStack(spacing: 6) {
                        if sessionSchedule.isStarting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(sessionSchedule.isStarting ? "Starting…" : "Start session now")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(sessionSchedule.isStarting)
                lastRunLabel
            }
        }
    }

    @ViewBuilder
    private var lastRunLabel: some View {
        switch sessionSchedule.lastRun {
        case .success(let date):
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accentCyan)
                Text(date, format: .dateTime.hour().minute())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            }
        case .failure(let detail, _):
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accentPrimary)
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        case .none:
            EmptyView()
        }
    }

    private func updateTrigger(_ mutate: (inout SessionTrigger) -> Void) {
        var trigger = settings.current.sessionTrigger
        mutate(&trigger)
        settings.setSessionTrigger(trigger)
    }

    private var triggerTimeBinding: Binding<Date> {
        Binding(
            get: {
                let trigger = settings.current.sessionTrigger
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

    // MARK: - Usage

    private var usageTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionTitle(
                title: "Usage Auto-Refresh",
                description: "Refresh the Claude usage indicator automatically on an interval."
            )
            infoCard("When enabled, Lumi re-checks your Claude limits every interval — but only "
                + "while you're actively using your Mac (recent keyboard/mouse input). It never runs "
                + "while the Mac is asleep, and each check counts against your subscription quota, "
                + "just like the manual refresh.")
            SettingsToggleRow(
                title: "Auto-Refresh",
                hint: "Re-check usage automatically while you're active",
                isOn: Binding(
                    get: { settings.current.usageAutoRefresh.enabled },
                    set: { value in updateUsageAutoRefresh { $0.enabled = value } }
                )
            ) {
                usageIntervalPicker
            }
            usageStatusRow
        }
    }

    private var usageIntervalPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Check interval")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
            SettingsSegmented(
                options: UsageAutoRefresh.allowedIntervals.map {
                    .init(value: $0, label: "\($0) min")
                },
                selection: Binding(
                    get: { settings.current.usageAutoRefresh.intervalMinutes },
                    set: { value in updateUsageAutoRefresh { $0.intervalMinutes = value } }
                )
            )
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var usageStatusRow: some View {
        if usage.isLoading {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            }
        } else if let message = usage.errorMessage {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accentPrimary)
                Text("Last check failed: \(message)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else if let fetched = usage.snapshot?.fetchedAt {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accentCyan)
                Text("Last checked")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Text(fetched, format: .dateTime.hour().minute())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    private func updateUsageAutoRefresh(_ mutate: (inout UsageAutoRefresh) -> Void) {
        var copy = settings.current.usageAutoRefresh
        mutate(&copy)
        settings.setUsageAutoRefresh(copy)
    }

    // MARK: - Shortcuts (salt-okunur referans, spec/22 §5.6)

    private var shortcutsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionTitle(
                title: "Keyboard Shortcuts",
                description: "Application shortcuts. Read-only reference."
            )
            VStack(spacing: 1) {
                ForEach(ShortcutReference.all) { ref in
                    shortcutRow(ref)
                }
            }
            .background(Theme.border) // satır araları 1px çizgi (v1 .shortcuts-list)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func shortcutRow(_ ref: ShortcutReference) -> some View {
        HStack(spacing: 16) {
            Text(ref.action)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(Array(ref.combos.enumerated()), id: \.offset) { index, combo in
                    if index > 0 {
                        Text("–")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.textMuted)
                    }
                    HStack(spacing: 3) {
                        ForEach(Array(combo.enumerated()), id: \.offset) { _, key in
                            Keycap(key: key)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Theme.bgDeep)
    }
}

/// v1 .settings-modal__close: 28×28, hover'da elevated zemin.
private struct SettingsCloseButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isHovering ? Theme.textPrimary : Theme.textMuted)
                .frame(width: 28, height: 28)
                .background(isHovering ? Theme.bgElevated : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// v1 .settings-nav__item: ikon + label; aktif soluk accent zemin + accent metin.
private struct SettingsNavItem: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(foreground)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(foreground)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var foreground: Color {
        if isActive { return Theme.accentPrimary }
        return isHovering ? Theme.textPrimary : Theme.textSecondary
    }

    private var background: Color {
        if isActive { return Theme.accentVivid.opacity(0.08) }
        return isHovering ? Theme.bgElevated : Color.clear
    }
}
