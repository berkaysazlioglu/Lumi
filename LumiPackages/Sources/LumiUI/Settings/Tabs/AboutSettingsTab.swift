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
            LumiField(title: "Updates", hint: "Checked against GitHub Releases at launch") {
                AboutUpdateStatus(store: updates, openRelease: shell.actions.openURL)
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

/// Güncelleme durumu satırı + eylemleri.
private struct AboutUpdateStatus: View {
    let store: AppUpdateStore
    let openRelease: @MainActor (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if let release = store.availableRelease {
                availableCard(release)
            } else {
                statusRow
            }
            LumiBrowseButton(
                icon: "arrow.clockwise",
                label: store.isChecking ? "Checking…" : "Check for Updates"
            ) {
                Task { await store.check() }
            }
            .disabled(store.isChecking)
            .opacity(store.isChecking ? 0.5 : 1)
        }
    }

    private func availableCard(_ release: AppRelease) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "sparkles")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.warning)
                .accessibilityHidden(true)
            Text("Lumi \(release.version.description) is available — you have \(store.currentVersion)")
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            LumiBrowseButton(icon: "arrow.down.circle", label: "Download") {
                openRelease(release.pageURL)
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.warning.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.warning.opacity(0.4), lineWidth: Theme.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var statusRow: some View {
        let presentation = Self.presentation(for: store.status)
        return HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: presentation.icon)
                .font(Theme.Typography.label)
                .foregroundStyle(presentation.color)
                .accessibilityHidden(true)
            Text(presentation.text)
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textMuted)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private static func presentation(
        for status: AppUpdateStore.Status
    ) -> (icon: String, color: Color, text: String) {
        switch status {
        case .idle:
            return ("circle.dashed", Theme.textMuted, "Not checked yet")
        case .checking:
            return ("arrow.clockwise", Theme.textMuted, "Checking GitHub Releases…")
        case .upToDate:
            return ("checkmark.circle", Theme.success, "You're on the latest version")
        case .available(let release):
            return ("sparkles", Theme.warning, "Lumi \(release.version.description) is available")
        case .developmentBuild(let release):
            return ("hammer", Theme.textMuted,
                    "Development build — latest release is \(release.version.description)")
        case .failed(let message):
            return ("exclamationmark.triangle", Theme.error, message)
        }
    }
}

#if DEBUG
#Preview("About") {
    SettingsTabPreview(.about)
}
#endif
