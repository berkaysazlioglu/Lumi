import AppKit
import LumiKit
import LumiState
import SwiftUI

/// Sürüm, sistem, linkler ve yeni sürüm kontrolü (karar 102). Menüdeki
/// `About Lumi` Settings'i doğrudan bu sekmede açar.
struct AboutSettingsTab: SettingsTabContent {
    static let tab: SettingsTab = .about

    private static var iconSide: CGFloat { Theme.scaled(56) }

    @Shell private var shell

    private let about = AppAboutInfo.current

    init() {}

    private var updates: AppUpdateStore { shell.appUpdate }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            identity
                .padding(.bottom, Theme.Spacing.xxl)
            LumiField(title: "Updates", hint: "Checked against GitHub Releases at launch and every 4 hours") {
                AboutUpdateStatus(
                    store: updates,
                    openRelease: shell.actions.openURL,
                    requestInstall: shell.requestInstallUpdate
                )
            }
            LumiField(title: "System", hint: nil) {
                AboutValue(text: about.system)
            }
            LumiField(title: "Links", hint: "Source code and downloadable builds", isLast: true) {
                HStack(spacing: Theme.Spacing.md) {
                    LumiBrowseButton(
                        icon: "chevron.left.forwardslash.chevron.right",
                        label: "GitHub Repository"
                    ) {
                        shell.actions.openURL(AppAboutInfo.repositoryURL)
                    }
                    LumiBrowseButton(icon: "arrow.down.circle", label: "Releases") {
                        shell.actions.openURL(AppAboutInfo.releasesURL)
                    }
                }
            }
        }
    }

    private var identity: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: Self.iconSide, height: Self.iconSide)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Lumi")
                    .font(Theme.Typography.mono(.headline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                AboutValue(text: "Version \(about.versionLine)")
            }
        }
    }
}

/// Seçilip kopyalanabilen değer metni (hata bildirirken sürümü yapıştırmak için).
private struct AboutValue: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Typography.bodyMono)
            .foregroundStyle(Theme.textSecondary)
            .textSelection(.enabled)
    }
}

#if DEBUG
#Preview("About") {
    SettingsTabPreview(.about)
}
#endif
