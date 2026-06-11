import LumiKit
import LumiState
import SwiftUI

/// Settings modal'ı (karar 3: macOS anlık uygulama — Save/Cancel YOK, her
/// değişiklik anında yazılır ve yan etkisi koordinatörden akar).
/// Shortcuts sekmesi yok: kısayolların tek kaynağı menüdür (design/03 §2).
struct SettingsView: View {
    private enum Tab: String, CaseIterable {
        case general = "General"
        case terminal = "Terminal"
        case notifications = "Notifications"
    }

    let settings: SettingsStore
    let chooseFolder: () async -> String?
    let onClose: () -> Void

    @State private var selectedTab: Tab = .general

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
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
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.bgElevated)
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(
                            selectedTab == tab ? Theme.textPrimary : Theme.textSecondary
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedTab == tab ? Theme.bgElevated : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(10)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .general: generalTab
        case .terminal: terminalTab
        case .notifications: notificationsTab
        }
    }

    // MARK: - General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsRow(title: "Projects Root", hint: "Birinci seviye alt dizinler repo olarak listelenir") {
                HStack(spacing: 8) {
                    Text(settings.current.projectsRoot.isEmpty
                        ? "(ayarlanmadı)" : settings.current.projectsRoot)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Browse…") {
                        Task { @MainActor in
                            if let path = await chooseFolder() {
                                settings.setProjectsRoot(path)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            settingsRow(title: "Additional Paths", hint: "root: alt dizinleri taranır · repo: tek başına eklenir") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(settings.current.additionalPaths) { entry in
                        HStack(spacing: 8) {
                            Text(entry.type.rawValue)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.accentPrimary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Theme.accentPrimary.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            Text(entry.path)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                settings.removeAdditionalPath(id: entry.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Theme.textMuted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack(spacing: 8) {
                        Button("Add Root…") { addPath(type: .root) }
                            .buttonStyle(.bordered)
                        Button("Add Repo…") { addPath(type: .repo) }
                            .buttonStyle(.bordered)
                    }
                }
            }

            settingsRow(title: "AI Provider", hint: "Yeni terminal ve action'larda kullanılacak CLI") {
                Picker("", selection: Binding(
                    get: { settings.current.aiProvider },
                    set: { settings.setProvider($0) }
                )) {
                    Text("Claude").tag(AgentProvider.claude)
                    Text("Codex").tag(AgentProvider.codex)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .labelsHidden()
            }
        }
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
        VStack(alignment: .leading, spacing: 18) {
            settingsRow(title: "Max Terminals", hint: "1–20; limit yalnız yeni spawn'ları etkiler") {
                Stepper(
                    "\(settings.current.maxTerminals)",
                    value: Binding(
                        get: { settings.current.maxTerminals },
                        set: { settings.setMaxTerminals($0) }
                    ),
                    in: 1...20
                )
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 120, alignment: .leading)
            }
            settingsRow(title: "Font Size", hint: "10–24px; yeni açılan terminallere uygulanır") {
                Stepper(
                    "\(settings.current.terminalFontSize) px",
                    value: Binding(
                        get: { settings.current.terminalFontSize },
                        set: { settings.setTerminalFontSize($0) }
                    ),
                    in: 10...24
                )
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 120, alignment: .leading)
            }
        }
    }

    // MARK: - Notifications

    private var notificationsTab: some View {
        let current = settings.current.notifications
        return VStack(alignment: .leading, spacing: 18) {
            settingsRow(title: "Waiting (unseen)", hint: "Asistan input beklerken anında bildirim + tekrar") {
                HStack(spacing: 12) {
                    Toggle("", isOn: Binding(
                        get: { settings.current.notifications.unseenEnabled },
                        set: { value in
                            var updated = current
                            updated.unseenEnabled = value
                            settings.setNotifications(updated)
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    intervalStepper(
                        value: current.unseenIntervalMinutes,
                        enabled: current.unseenEnabled
                    ) { minutes in
                        var updated = current
                        updated.unseenIntervalMinutes = minutes
                        settings.setNotifications(updated)
                    }
                }
            }
            settingsRow(title: "Waiting (seen)", hint: "Görülmüş ama yanıtlanmamış terminaller için tekrar") {
                HStack(spacing: 12) {
                    Toggle("", isOn: Binding(
                        get: { settings.current.notifications.seenEnabled },
                        set: { value in
                            var updated = current
                            updated.seenEnabled = value
                            settings.setNotifications(updated)
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    intervalStepper(
                        value: current.seenIntervalMinutes,
                        enabled: current.seenEnabled
                    ) { minutes in
                        var updated = current
                        updated.seenIntervalMinutes = minutes
                        settings.setNotifications(updated)
                    }
                }
            }
        }
    }

    private func intervalStepper(
        value: Int,
        enabled: Bool,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        Stepper(
            "\(value) dk",
            value: Binding(get: { value }, set: onChange),
            in: 1...60
        )
        .font(.system(size: 12, design: .monospaced))
        .disabled(!enabled)
        .frame(width: 110, alignment: .leading)
    }

    private func settingsRow<Content: View>(
        title: String,
        hint: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
            content()
            Text(hint)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        }
    }
}
