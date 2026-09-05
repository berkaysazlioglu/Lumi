import SwiftUI

/// Settings modal'ının kabuğu (Faz 7.3): karartma + panel + navigasyon +
/// içerik anahtarı. 820 satırlık `SettingsView` burada ~100 satıra indi;
/// sekmelerin gövdeleri `Settings/Tabs/` altında yaşar ve her biri
/// ihtiyacı olan store'u `@Shell`'den okur.
///
/// Kaydetme modeli: macOS anlık uygulama (karar 3) — Save/Cancel footer'ı YOK.
struct SettingsShell: View {
    private static let panelWidth: CGFloat = 700
    private static let panelHeight: CGFloat = 600
    private static let navigationWidth: CGFloat = 180

    @Shell private var shell

    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        ModalOverlay(onDismiss: close) {
            Panel(variant: .modal) {
                VStack(spacing: 0) {
                    header
                    divider
                    HStack(spacing: 0) {
                        SettingsNav(selection: $selectedTab)
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
