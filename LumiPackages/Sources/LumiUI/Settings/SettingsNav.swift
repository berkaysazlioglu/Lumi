import SwiftUI

/// Settings panelinin sol dikey navigasyonu (Faz 7.3).
struct SettingsNav: View {
    @Binding var selection: SettingsTab

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            ForEach(SettingsTab.allCases) { tab in
                SettingsNavItem(tab: tab, isActive: selection == tab) {
                    selection = tab
                }
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.xl)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }
}

/// v1 `.settings-nav__item`: ikon + label; aktif soluk accent zemin + accent metin.
private struct SettingsNavItem: View {
    let tab: SettingsTab
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        HoverReader { isHovering in
            Button(action: action) {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: tab.icon)
                        .font(Theme.Typography.ui(.base))
                        .foregroundStyle(foreground(isHovering: isHovering))
                        .frame(width: Theme.Spacing.xl)
                        .accessibilityHidden(true)
                    Text(tab.title)
                        .font(Theme.Typography.mono(.base, weight: .medium))
                        .foregroundStyle(foreground(isHovering: isHovering))
                    Spacer(minLength: 0)
                }
                // 10pt: ölçek dışı ara değer (v1 paritesi korunuyor).
                .padding(10)
                .background(background(isHovering: isHovering))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func foreground(isHovering: Bool) -> Color {
        if isActive { return Theme.accentPrimary }
        return isHovering ? Theme.textPrimary : Theme.textSecondary
    }

    private func background(isHovering: Bool) -> Color {
        if isActive { return Theme.accentVivid.opacity(0.08) }
        return isHovering ? Theme.bgElevated : Color.clear
    }
}

#if DEBUG
#Preview("SettingsNav") {
    SettingsNav(selection: .constant(.terminal))
        .frame(width: 180, height: 420)
        .background(Theme.bgSurface)
}
#endif
