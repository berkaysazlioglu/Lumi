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
        case shortcuts = "Shortcuts"

        var id: String { rawValue }

        /// v1 lucide ikonlarının SF Symbol karşılığı.
        var icon: String {
            switch self {
            case .general: return "folder"
            case .terminal: return "terminal"
            case .appearance: return "paintpalette"
            case .notifications: return "bell"
            case .shortcuts: return "keyboard"
            }
        }
    }

    let settings: SettingsStore
    let workspace: WorkspaceStore
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
        case .shortcuts: shortcutsTab
        }
    }

    // MARK: - General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionTitle(
                title: "General",
                description: "Repo keşfi ve varsayılan AI sağlayıcısı."
            )
            SettingsField(
                title: "Projects Root",
                hint: "Birinci seviye alt dizinler repo olarak listelenir"
            ) {
                HStack(spacing: 8) {
                    Text(settings.current.projectsRoot.isEmpty
                        ? "(ayarlanmadı)" : settings.current.projectsRoot)
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
                hint: "root: alt dizinleri taranır · repo: tek başına eklenir"
            ) {
                additionalPathsField
            }
            SettingsField(
                title: "AI Provider",
                hint: "Yeni terminal ve action'larda kullanılacak CLI",
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
                description: "Terminal limiti ve yazı tipi boyutu."
            )
            SettingsField(
                title: "Max Terminals",
                hint: "1–20; limit yalnız yeni spawn'ları etkiler"
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
                title: "Font Size",
                hint: "10–24px; yeni açılan terminallere uygulanır",
                isLast: true
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
        }
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionTitle(
                title: "Appearance",
                description: "Panel görünürlüğü. Değişiklik anında uygulanır ve hatırlanır."
            )
            SettingsToggleRow(
                title: "Left Sidebar",
                hint: "Sessions · Project Context · Quick Actions paneli",
                isOn: Binding(
                    get: { workspace.leftSidebarOpen },
                    set: { workspace.setLeftSidebarOpen($0) }
                )
            )
            SettingsToggleRow(
                title: "Right Sidebar",
                hint: "Git paneli (Commits · Changes)",
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
                description: "Asistan input beklerken tekrarlı bildirim aralıkları."
            )
            infoCard("Bildirimler yalnız sistem izni verildiğinde görünür. Aralık, "
                + "terminal beklemede kaldığı sürece tekrar eder.")
            SettingsToggleRow(
                title: "Waiting (unseen)",
                hint: "Görülmemiş bekleyen terminaller için anında bildirim + tekrar",
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
                hint: "Görülmüş ama yanıtlanmamış terminaller için tekrar",
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
            Text("dk")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        }
    }

    // MARK: - Shortcuts (salt-okunur referans, spec/22 §5.6)

    private var shortcutsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionTitle(
                title: "Keyboard Shortcuts",
                description: "Uygulamadaki kısayollar. Salt-okunur referans."
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
