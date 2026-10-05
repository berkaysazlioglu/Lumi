import LumiKit
import SwiftUI

/// Aktif checkout'un favori dosyaları (karar 107). Üretim bölgesinde hızlı
/// komutların (karar 96) SOLUNDA, aynı çerçeveli/dolgusuz dilde durur:
/// `☆ Files ⌄` tıklanınca favoriler alt alta listelenir.
public struct FavoriteFilesToolbarItem: View {
    @Shell private var shell
    @State private var isMenuOpen = false

    public init() {}

    public var body: some View {
        if let target = QuickCommandTarget.active(in: shell) {
            Button { isMenuOpen.toggle() } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "star")
                        .font(Theme.Typography.ui(.caption, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("Files")
                        .font(Theme.Typography.mono(.label, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(Theme.Typography.ui(.micro, weight: .bold))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: TopBarMetrics.controlHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(HoverButtonStyle(hoverBackground: Theme.bgElevated, cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(Theme.border, lineWidth: Theme.Stroke.hairline)
                    .allowsHitTesting(false)
            )
            .help("Favorite files")
            .accessibilityLabel("Favorite files")
            .popover(isPresented: $isMenuOpen, arrowEdge: .bottom) {
                FavoriteFilesMenu(
                    projectPath: target.projectPath,
                    checkoutPath: target.context.path,
                    isCheckoutMissing: target.isMissing,
                    dismiss: { isMenuOpen = false }
                )
            }
        }
    }
}
