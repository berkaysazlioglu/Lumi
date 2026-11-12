import LumiKit
import LumiState
import SwiftUI

/// Sol üst bölümün satırlarını sürükle-bırakla sıralar (karar 151).
///
/// Satır, bölümdeki herhangi bir satırın üstüne bırakılınca onun yerine
/// geçer (aşağı sürüklenince arkasına, yukarı sürüklenince önüne düşer).
/// Yük, `SidebarNavigationItem.key`'dir; bölüme ait olmayan metin bırakılırsa
/// reddedilir. Sıra `LayoutStore`'da tutulur ve `ui-state`'e iner.
private struct SidebarNavigationReorder: ViewModifier {
    let item: SidebarNavigationItem
    let title: String
    let isEnabled: Bool

    @Shell private var shell
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .draggable(item.key) { preview }
                .dropDestination(for: String.self) { payloads, _ in
                    drop(payloads)
                } isTargeted: { isTargeted = $0 }
                .overlay {
                    if isTargeted {
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .strokeBorder(Theme.accentPrimary, lineWidth: Theme.Stroke.graph)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        } else {
            content
        }
    }

    private var preview: some View {
        Text(title)
            .font(Theme.Typography.bodyMono)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func drop(_ payloads: [String]) -> Bool {
        guard let moving = payloads.lazy.compactMap(SidebarNavigationItem.init(key:)).first,
              moving != item else { return false }
        let views = shell.terminals.customViews.views.map(\.id)
        shell.layout.moveSidebarNavigationItem(moving, onto: item, views: views)
        return true
    }
}

extension View {
    /// Karar 151: satırı sol üst bölümde sürüklenebilir ve bırakılabilir yapar.
    func sidebarNavigationReorder(_ item: SidebarNavigationItem, title: String, isEnabled: Bool = true) -> some View {
        modifier(SidebarNavigationReorder(item: item, title: title, isEnabled: isEnabled))
    }
}
