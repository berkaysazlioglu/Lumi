import SwiftUI

/// Settings modal'ının kabuğu (Faz 7.3): karartma + panel + navigasyon +
/// içerik anahtarı. 820 satırlık `SettingsView` burada ~100 satıra indi;
/// sekmelerin gövdeleri `Settings/Tabs/` altında yaşar ve her biri
/// ihtiyacı olan store'u `@Shell`'den okur.
///
/// Kaydetme modeli: macOS anlık uygulama (karar 3) — Save/Cancel footer'ı YOK.
struct SettingsShell: View {
    /// Karar 55 (kullanıcı düzeltmesi): form satırları 700×600'de sıkışıyordu.
    private static var panelWidth: CGFloat { Theme.scaled(860) }
    private static var panelHeight: CGFloat { Theme.scaled(720) }
    /// En uzun sekme adı ("Notifications") tek satıra sığmalı — 180'de son
    /// harf alt satıra düşüyordu (karar 55 kullanıcı düzeltmesi).
    private static var navigationWidth: CGFloat { Theme.scaled(200) }

    @Shell private var shell

    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        ModalOverlay(onDismiss: close) {
            Panel(variant: .modal) {
                VStack(spacing: 0) {
                    header
                    divider
                    HStack(spacing: 0) {
                        SettingsNav(selection: $selectedTab, badgedTabs: badgedTabs)
                            .frame(width: Self.navigationWidth)
                        Rectangle()
                            .fill(Theme.border)
                            .frame(width: Theme.Stroke.hairline)
                        content
                    }
                }
            }
            .frame(width: Self.panelWidth, height: Self.panelHeight)
        }
        // Karar 56: popover'daki "Manage Accounts…" paneli doğrudan ilgili
        // sekmede açar; istek bir kez tüketilir.
        .onAppear(perform: applyRequestedTab)
        // Karar 102: panel açıkken menüden `About Lumi` / `Settings…` gelirse
        // de istenen sekmeye geçilir.
        .onChange(of: shell.dialogs.requestedSettingsTab) { _, _ in applyRequestedTab() }
    }

    private var badgedTabs: Set<SettingsTab> {
        shell.appUpdate.availableRelease == nil ? [] : [.about]
    }

    private func applyRequestedTab() {
        if let raw = shell.dialogs.consumeRequestedSettingsTab(),
           let tab = SettingsTab(rawValue: raw) {
            selectedTab = tab
        }
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(Theme.Typography.mono(.headline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            IconButton(
                systemName: "xmark",
                label: "Close settings",
                side: 28,
                cornerRadius: Theme.Radius.md,
                action: close
            )
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.xl)
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
    }

    private var content: some View {
        ScrollView {
            selectedTab.content
                .padding(.horizontal, Theme.Spacing.xxxl)
                .padding(.vertical, Theme.Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func close() {
        shell.dialogs.isSettingsOpen = false
    }
}

#if DEBUG
#Preview("SettingsShell") {
    SettingsShell()
        .frame(width: 900, height: 700)
        .environment(\.shell, ShellContext.preview())
}
#endif
