import SwiftUI

/// İkon + metinli ikincil buton (v1 `.settings-browse-btn`): elevated zemin,
/// hover'da accent-deep. Faz 7.2'de hover state'i `HoverButtonStyle`'a devredildi.
struct LumiBrowseButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        HoverReader { isHovering in
            Button(action: action) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: icon)
                        .font(Theme.Typography.label)
                        .accessibilityHidden(true)
                    Text(label)
                        .font(Theme.Typography.bodyMono)
                }
                .foregroundStyle(isHovering ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(isHovering ? Theme.accentDeep : Theme.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(
                            isHovering ? Theme.accentDeep : Theme.border,
                            lineWidth: Theme.Stroke.hairline
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

#if DEBUG
#Preview("LumiBrowseButton") {
    HStack(spacing: Theme.Spacing.md) {
        LumiBrowseButton(icon: "folder", label: "Browse") {}
        LumiBrowseButton(icon: "folder.badge.gearshape", label: "Add Repository") {}
    }
    .padding(Theme.Spacing.xxl)
    .background(Theme.bgSurface)
}
#endif
