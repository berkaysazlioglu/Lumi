import SwiftUI

/// Tema uyumlu açılır menü (Orca dropdown paritesi).
///
/// Native `Menu`/`NSMenu` sistem görünümüyle açılıyordu ve koyu panelin
/// içinde yabancı duruyordu (Explorer görünüm seçenekleri şikâyeti). Bu menü
/// `.popover` içinde kendi satırlarını çizer: eylem, onay işaretli toggle,
/// bölüm başlığı ve ayraç. Satırlar hover'da `bgDeep` zeminle aydınlanır.
struct PopoverMenu: View {
    enum Item {
        case action(String, icon: String? = nil, isDestructive: Bool = false, isEnabled: Bool = true, action: () -> Void)
        case toggle(String, isOn: Bool, isEnabled: Bool = true, action: () -> Void)
        case section(String)
        case divider
    }

    let items: [Item]
    /// Bir eylem seçilince popover'ı kapatmak için.
    var dismiss: () -> Void = {}

    static let width: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
            // Konum bazlı kimlik: menü içeriği sabit sırada gelir, ayraçların adı yok.
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in row(item) }
        }
        .padding(Theme.Spacing.sm)
        .frame(width: Self.width)
        .background(Theme.bgElevated)
    }

    @ViewBuilder
    private func row(_ item: Item) -> some View {
        switch item {
        case .action(let title, let icon, let isDestructive, let isEnabled, let action):
            PopoverMenuRow(
                title: title, icon: icon, trailingCheck: nil,
                isDestructive: isDestructive, isEnabled: isEnabled
            ) { dismiss(); action() }
        case .toggle(let title, let isOn, let isEnabled, let action):
            PopoverMenuRow(
                title: title, icon: nil, trailingCheck: isOn,
                isDestructive: false, isEnabled: isEnabled, action: action
            )
        case .section(let title):
            Text(title.uppercased())
                .font(Theme.Typography.ui(.caption, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.textMuted)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xxs)
        case .divider:
            Rectangle()
                .fill(Theme.border)
                .frame(height: Theme.Stroke.hairline)
                .padding(.vertical, Theme.Spacing.xs)
        }
    }
}

private struct PopoverMenuRow: View {
    let title: String
    let icon: String?
    /// `nil` → eylem satırı; değer → toggle satırı (işaret sağda).
    let trailingCheck: Bool?
    let isDestructive: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(Theme.Typography.ui(.label))
                        .frame(width: Theme.Row.iconColumn)
                        .accessibilityHidden(true)
                }
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
                if let trailingCheck {
                    Image(systemName: "checkmark")
                        .font(Theme.Typography.ui(.caption, weight: .bold))
                        .opacity(trailingCheck ? 1 : 0)
                        .accessibilityHidden(true)
                }
            }
            .font(Theme.Typography.ui(.body))
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Row.compact + Theme.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(
            HoverButtonStyle(
                foreground: isDestructive ? Theme.error : Theme.textPrimary,
                hoverForeground: isDestructive ? Theme.error : Theme.textPrimary,
                background: .clear,
                hoverBackground: Theme.bgDeep,
                cornerRadius: Theme.Radius.sm
            )
        )
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : Self.disabledOpacity)
        .accessibilityAddTraits(trailingCheck == true ? .isSelected : [])
    }

    private static let disabledOpacity = 0.4
}

#if DEBUG
#Preview("PopoverMenu") {
    PopoverMenu(items: [
        .action("New File…", icon: "doc.badge.plus", action: {}),
        .action("New Folder…", icon: "folder.badge.plus", action: {}),
        .section("View Mode"),
        .toggle("Unity Assets only", isOn: true, action: {}),
        .toggle("Show Dotfiles", isOn: false, action: {}),
        .divider,
        .action("Reveal Project in Finder", icon: "folder", action: {}),
    ])
    .padding(Theme.Spacing.xxl)
    .background(Theme.bgSurface)
}
#endif
