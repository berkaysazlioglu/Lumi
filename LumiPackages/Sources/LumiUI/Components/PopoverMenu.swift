import SwiftUI

/// Tema uyumlu açılır menü (Orca dropdown paritesi).
///
/// Native `Menu`/`NSMenu` sistem görünümüyle açılıyordu ve koyu panelin
/// içinde yabancı duruyordu (Explorer görünüm seçenekleri şikâyeti). Bu menü
/// `.popover` içinde kendi satırlarını çizer: eylem, onay işaretli toggle,
/// bölüm başlığı, ayraç ve alt menü. Satırlar hover'da `bgDeep` zeminle aydınlanır.
///
/// Alt menü (karar 93): satırın üstüne gelince sağda ikinci bir `PopoverMenu`
/// açılır; başka bir satıra gelinince kapanır. Satırdan çıkmak (alt menüye
/// geçmek) kapatmaz — alt popover ayrı bir penceredir.
struct PopoverMenu: View {
    enum Item {
        case action(String, icon: String? = nil, isDestructive: Bool = false, isEnabled: Bool = true, action: () -> Void)
        case toggle(String, isOn: Bool, isEnabled: Bool = true, action: () -> Void)
        case section(String)
        case divider
        /// Tıklanamayan bilgi satırı (yükleniyor / hata / sonuç yok).
        case note(String)
        /// Hover'da sağda açılan alt menü; içindeki eylem ana menüyü de kapatır.
        case submenu(String, icon: String? = nil, isEnabled: Bool = true, items: [Item])
    }

    let items: [Item]
    /// Bir eylem seçilince popover'ı kapatmak için.
    var dismiss: () -> Void = {}
    /// `nil` → içerik kadar genişler (uzun dal adlarının kırpılmaması için).
    var width: CGFloat? = PopoverMenu.width

    static var width: CGFloat { Theme.scaled(220) }

    /// Açık alt menünün `items` içindeki konumu.
    @State private var openSubmenu: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
            // Konum bazlı kimlik: menü içeriği sabit sırada gelir, ayraçların adı yok.
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                row(item, index: index)
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(width: width)
        .frame(minWidth: width == nil ? Self.width : nil, alignment: .leading)
        .background(Theme.bgElevated)
    }

    @ViewBuilder
    private func row(_ item: Item, index: Int) -> some View {
        switch item {
        case .submenu(let title, let icon, let isEnabled, let items):
            PopoverSubmenuRow(
                title: title, icon: icon, isEnabled: isEnabled,
                isOpen: Binding(
                    get: { openSubmenu == index },
                    set: { openSubmenu = $0 ? index : (openSubmenu == index ? nil : openSubmenu) }
                ),
                items: items, dismiss: dismiss
            )
        default:
            plainRow(item)
                .onHover { if $0 { openSubmenu = nil } }
        }
    }

    @ViewBuilder
    private func plainRow(_ item: Item) -> some View {
        switch item {
        case .submenu:
            EmptyView()
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
        case .note(let text):
            Text(text)
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textMuted)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
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

/// Alt menü satırı: sağda chevron; hover ya da tık alt menüyü açar ve açıkken
/// satır vurgulu kalır.
private struct PopoverSubmenuRow: View {
    let title: String
    let icon: String?
    let isEnabled: Bool
    @Binding var isOpen: Bool
    let items: [PopoverMenu.Item]
    let dismiss: () -> Void

    var body: some View {
        HoverReader { isHovering in
            Button { isOpen = true } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    if let icon {
                        Image(systemName: icon)
                            .font(Theme.Typography.ui(.label))
                            .frame(width: Theme.Row.iconColumn)
                            .accessibilityHidden(true)
                    }
                    Text(title).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.ui(.caption, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                        .accessibilityHidden(true)
                }
                .font(Theme.Typography.ui(.body))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: Theme.Row.compact + Theme.Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((isOpen || isHovering) && isEnabled ? Theme.bgDeep : .clear)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onChange(of: isHovering) { _, hovering in
                if hovering && isEnabled { isOpen = true }
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .popover(isPresented: $isOpen, arrowEdge: .trailing) {
            PopoverMenu(items: items, dismiss: dismiss)
        }
        .accessibilityLabel("\(title) submenu")
    }
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
