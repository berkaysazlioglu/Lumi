import LumiKit
import LumiState
import SwiftUI

/// Sağ alttaki güncelleme kartı (karar 118; Orca `UpdateCard` paritesi).
///
/// Toast yığınının EN ALTINDA durur (`ToastOverlayHost`): geçici toast'lar
/// kartın üstüne dizilir, kartı örtmez. İki hâli vardır:
/// - **Hazır:** sürüm indirilip doğrulandı → `Restart to Update` onay
///   dialogunu açar (kurulum kendiliğinden asla yapılmaz).
/// - **Elle indirme:** bu kopya bulunduğu yerden kendini güncelleyemiyor →
///   `Download` release sayfasını açar.
///
/// Kapatma (✕) kartı bu sürüm için bu oturumda gizler; alt bar segmenti
/// (`AppUpdateStatusItem`) dönüş yolu olarak kalır.
public struct AppUpdateCard: View {
    @Shell private var shell

    public init() {}

    private var store: AppUpdateStore { shell.appUpdate }

    private static var width: CGFloat { Theme.scaled(340) }

    public var body: some View {
        if let release = store.availableRelease {
            Panel(variant: .floating) {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    header(isReady: store.stagedUpdate != nil)
                    Text(message(for: release))
                        .font(Theme.Typography.labelMono)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let failure = store.lastInstallFailure {
                        Text("Last update attempt failed: \(failure)")
                            .font(Theme.Typography.labelMono)
                            .foregroundStyle(Theme.error)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    actions(for: release)
                }
                .padding(Theme.Spacing.lg)
            }
            .frame(width: Self.width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.move(edge: .trailing).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(store.stagedUpdate != nil ? "Update ready" : "Update available")
        }
    }

    private func header(isReady: Bool) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "arrow.down.circle.fill")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.accentPrimary)
                .accessibilityHidden(true)
            Text(isReady ? "Update Ready" : "Update Available")
                .font(Theme.Typography.mono(.body, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            IconButton(
                systemName: "xmark",
                label: "Remind me later",
                size: .micro,
                side: nil,
                showsHoverBackground: false
            ) {
                store.dismissCard()
            }
        }
    }

    private func message(for release: AppRelease) -> String {
        let versions = "Lumi \(release.version.description) — you have \(store.currentVersion)."
        if store.stagedUpdate != nil {
            return "\(versions) Downloaded and ready to install."
        }
        return "\(versions) Lumi can't update itself from its current location. "
            + "Move it to Applications, or download the new version."
    }

    private func actions(for release: AppRelease) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            LumiBrowseButton(icon: "doc.text", label: "Release Notes") {
                shell.actions.openURL(release.pageURL)
            }
            Spacer(minLength: 0)
            if store.stagedUpdate != nil {
                LumiActionButton(title: "Restart to Update", kind: .primary) {
                    shell.requestInstallUpdate()
                }
            } else {
                LumiActionButton(title: "Download", kind: .primary) {
                    shell.actions.openURL(release.pageURL)
                }
            }
        }
    }
}

/// Alt bar segmenti (karar 118): hazır bir güncelleme varken hep görünür —
/// kart kapatılsa ya da `Install on Quit` seçilse de dönüş yolu budur.
public struct AppUpdateStatusItem: View {
    @Shell private var shell

    public init() {}

    private var isScheduled: Bool { shell.appUpdate.installTiming == .onQuit }

    public var body: some View {
        if let staged = shell.appUpdate.stagedUpdate {
            let version = staged.release.version.description
            Button { shell.requestInstallUpdate() } label: {
                StatusBarSegmentLabel {
                    Image(systemName: "arrow.down.circle")
                        .font(Theme.Typography.ui(.label))
                        .foregroundStyle(Theme.accentPrimary)
                        .accessibilityHidden(true)
                    Text(isScheduled ? "Installs on quit" : "Update ready")
                }
            }
            .buttonStyle(StatusBarSegmentStyle())
            .help(
                isScheduled
                    ? "Lumi \(version) will be installed when you quit Lumi"
                    : "Lumi \(version) is ready to install"
            )
            .accessibilityLabel(isScheduled ? "Lumi \(version) installs on quit" : "Lumi \(version) update ready")
        }
    }
}
