import LumiKit
import SwiftUI

/// Orta alanın boş durumundaki kare eylem butonu (karar 119): üstte ikon,
/// altta etiket. `LumiBrowseButton` ile aynı dil — elevated zemin + hairline
/// kenarlık, hover'da accent-deep — yalnız kare ve kart yarıçaplı.
struct TileButton<Icon: View>: View {
    let title: String
    /// Etiketin altındaki soluk ikinci satır (ör. terminalin açılacağı konum).
    var subtitle: String?
    let action: () -> Void
    @ViewBuilder var icon: () -> Icon

    init(
        _ title: String,
        subtitle: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder icon: @escaping () -> Icon
    ) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.icon = icon
    }

    private static var side: CGFloat { Theme.scaled(132) }

    var body: some View {
        HoverReader { isHovering in
            Button(action: action) {
                VStack(spacing: Theme.Spacing.lg) {
                    icon()
                        .frame(height: Theme.Spacing.xxxl)
                        .accessibilityHidden(true)
                    VStack(spacing: Theme.Spacing.xxs) {
                        Text(title)
                            .font(Theme.Typography.bodyMono)
                            .multilineTextAlignment(.center)
                        if let subtitle {
                            Text(subtitle)
                                .font(Theme.Typography.captionMono)
                                .foregroundStyle(Theme.textMuted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .foregroundStyle(isHovering ? Theme.textPrimary : Theme.textSecondary)
                .padding(Theme.Spacing.md)
                .frame(width: Self.side, height: Self.side)
                .background(isHovering ? Theme.accentDeep : Theme.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg)
                        .stroke(isHovering ? Theme.accentDeep : Theme.border, lineWidth: Theme.Stroke.hairline)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
        }
    }
}

#if DEBUG
#Preview("TileButton") {
    HStack(spacing: Theme.Spacing.lg) {
        TileButton("Add Project Root", action: {}) {
            Image(systemName: "folder.badge.plus").font(Theme.Typography.ui(.display))
        }
        TileButton("New Claude", subtitle: "in ~", action: {}) {
            ProviderIcon(provider: .claude, size: .display)
        }
    }
    .padding(Theme.Spacing.xxl)
    .background(Theme.bgSurface)
}
#endif
