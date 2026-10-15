import LumiKit
import LumiState
import SwiftUI

/// Sağ alttaki güncelleme kartı (karar 118; Orca `UpdateCard` paritesi).
///
/// Toast yığınının EN ALTINDA durur (`ToastOverlayHost`): geçici toast'lar
/// kartın üstüne dizilir, kartı örtmez. İki hâli vardır:
/// - **Hazır:** sürüm indirilip doğrulandı → `Restart` onay
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
    private var isReady: Bool { store.stagedUpdate != nil }

    private static var width: CGFloat { Theme.scaled(360) }
    private static var badgeSide: CGFloat { Theme.scaled(30) }
    private static let badgeOpacity = 0.15

    public var body: some View {
        if let release = store.availableRelease {
            Panel(variant: .floating) {
                VStack(alignment: .leading, spacing: 0) {
                    header(release)
                    Text(detail)
                        .font(Theme.Typography.labelMono)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Spacing.md)
                    if let failure = store.lastInstallFailure {
                        Text("Last attempt failed: \(failure)")
                            .font(Theme.Typography.labelMono)
                            .foregroundStyle(Theme.error)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(.top, Theme.Spacing.sm)
                    }
                    Rectangle()
                        .fill(Theme.border)
                        .frame(height: Theme.Stroke.hairline)
                        .padding(.vertical, Theme.Spacing.lg)
                    actions(release)
                }
                .padding(Theme.Spacing.lg)
            }
            .frame(width: Self.width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.move(edge: .trailing).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(isReady ? "Update ready" : "Update available")
        }
    }

    private func header(_ release: AppRelease) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            Image(systemName: "arrow.down")
                .font(Theme.Typography.ui(.label, weight: .bold))
                .foregroundStyle(Theme.accentPrimary)
                .frame(width: Self.badgeSide, height: Self.badgeSide)
                .background(Circle().fill(Theme.accentPrimary.opacity(Self.badgeOpacity)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(isReady ? "Update Ready" : "Update Available")
                    .font(Theme.Typography.mono(.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Lumi \(release.version.description)  ·  you have \(store.currentVersion)")
                    .font(Theme.Typography.captionMono)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.sm)
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

    private var detail: String {
        if isReady {
            return "Downloaded and verified. Restart Lumi to install it — or choose to install it when you quit."
        }
        return "Lumi can't update itself from its current location. "
            + "Move it to Applications, or download the new version."
    }

    private func actions(_ release: AppRelease) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Button { shell.actions.openURL(release.pageURL) } label: {
                HStack(spacing: Theme.Spacing.xxs) {
                    Text("Release Notes")
                    Image(systemName: "arrow.up.right")
                        .accessibilityHidden(true)
                }
                .font(Theme.Typography.labelMono)
                .padding(.vertical, Theme.Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(HoverButtonStyle(
                foreground: Theme.textMuted, hoverForeground: Theme.textPrimary,
                background: .clear, hoverBackground: .clear, cornerRadius: Theme.Radius.sm
            ))
            Spacer(minLength: Theme.Spacing.md)
            if isReady {
                LumiActionButton(title: "Restart", kind: .primary) {
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
