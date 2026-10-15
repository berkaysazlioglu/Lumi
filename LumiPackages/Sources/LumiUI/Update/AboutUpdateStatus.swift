import LumiKit
import LumiState
import SwiftUI

/// Güncelleme durumu satırı + eylemleri.
struct AboutUpdateStatus: View {
    let store: AppUpdateStore
    let openRelease: @MainActor (URL) -> Void
    let requestInstall: @MainActor () -> Void

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

    /// Karar 118: kart güncellemenin aşamasını söyler — indiriliyor, hazır
    /// (kurulum onayı), indirilemedi (yeniden dene) ya da elle indirilmeli.
    private func availableCard(_ release: AppRelease) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "sparkles")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Lumi \(release.version.description) is available — you have \(store.currentVersion)")
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = availableDetail {
                    Text(detail)
                        .font(Theme.Typography.labelMono)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
            availableAction(release)
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.warning.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.warning.opacity(0.4), lineWidth: Theme.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var availableDetail: String? {
        switch store.status {
        case .downloading:
            return "Downloading…"
        case .readyToInstall:
            if store.installTiming == .onQuit { return "Will be installed when you quit Lumi." }
            return "Downloaded and ready to install."
        case .downloadFailed(_, let message):
            return message
        case .available:
            return Self.manualHint(store.installSupport)
        default:
            return nil
        }
    }

    @ViewBuilder
    private func availableAction(_ release: AppRelease) -> some View {
        switch store.status {
        case .downloading:
            ProgressView().controlSize(.small)
        case .readyToInstall:
            LumiBrowseButton(icon: "arrow.clockwise.circle", label: "Restart") {
                requestInstall()
            }
        case .downloadFailed:
            LumiBrowseButton(icon: "arrow.clockwise", label: "Retry") {
                Task { await store.retryDownload() }
            }
        default:
            LumiBrowseButton(icon: "arrow.down.circle", label: "Download") {
                openRelease(release.pageURL)
            }
        }
    }

    /// Bu kopya kendini neden güncelleyemiyor (elle indirme yolu).
    private static func manualHint(_ support: AppUpdateInstallSupport) -> String? {
        switch support {
        case .supported: nil
        case .unsignedBuild: "This build updates manually (not signed with Developer ID)."
        case .readOnlyLocation(let path): "Lumi can't update itself at \(path). Move it to Applications."
        }
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
        case .available(let release), .downloading(let release), .downloadFailed(let release, _):
            return ("sparkles", Theme.warning, "Lumi \(release.version.description) is available")
        case .readyToInstall(let staged):
            return ("sparkles", Theme.warning, "Lumi \(staged.release.version.description) is ready to install")
        case .developmentBuild(let release):
            return ("hammer", Theme.textMuted,
                    "Development build — latest release is \(release.version.description)")
        case .failed(let message):
            return ("exclamationmark.triangle", Theme.error, message)
        }
    }
}
