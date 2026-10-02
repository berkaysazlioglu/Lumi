import LumiKit
import LumiState
import SwiftUI

/// Sol panelin üst öğesi (karar 55 — eski `SessionsPanelItem`'ın yeri).
///
/// Sessions listesi kaldırıldı: canlı ajanlar zaten Projects panelinde
/// checkout başına listeleniyordu. Yerine Tasks ve Remote **satırları** geldi;
/// her biri orta alanın bir route'udur — tıklama terminal ızgarasının yerine o
/// route'un görünümünü getirir. Geri dönüş ayrı bir kontrol istemez: Projects
/// panelinden bir proje/workspace/ajan seçmek repo route'unu geri açar.
///
/// Karar 103: en üstte All Terminals satırı — tüm projelerin terminalleri tek
/// ızgarada; yanında toplam terminal sayısı.
public struct TasksPanelItem: View {
    /// Öğenin en küçük yüksekliği — eski Sessions bölümünün (başlık + 180pt
    /// sabit liste) kapladığı alan. İki satır bu alanı doldurmaz; yuvanın
    /// üst payı korunsun ve altındaki Projects paneli yerinden oynamasın diye
    /// taban yükseklik sabit tutulur (kullanıcı düzeltmesi).
    private static var minContentHeight: CGFloat { Theme.scaled(208) }

    @Shell private var shell

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            row(
                title: AllTerminalsRoute.title,
                icon: AllTerminalsRoute.icon,
                route: AllTerminalsRoute.route,
                count: shell.terminals.totalCount
            )
            ForEach(TasksPanelSection.allCases, id: \.self) { section in
                row(title: section.title, icon: section.icon, route: .content(section.routeID))
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.minContentHeight, alignment: .top)
        .padding(Theme.Spacing.lg)
    }

    /// `count`: satırın sağındaki sayı; `nil` ya da 0 ise çizilmez.
    private func row(title: String, icon: String, route: WorkspaceRoute, count: Int? = nil) -> some View {
        let isActive = shell.navigation.activeRoute == route
        return HoverReader { isHovering in
            Button { shell.navigation.setRoute(route) } label: {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: icon)
                        .font(Theme.Typography.ui(.body))
                        .accessibilityHidden(true)
                    Text(title)
                        .font(Theme.Typography.bodyMono)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let count, count > 0 {
                        Text("\(count)")
                            .font(Theme.Typography.mono(.label))
                            .foregroundStyle(Theme.textMuted)
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(nameColor(isActive: isActive, isHovering: isHovering))
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(isActive || isHovering ? Theme.bgElevated : Color.clear)
                .overlay(alignment: .leading) {
                    if isActive {
                        Rectangle().fill(Theme.accentPrimary).frame(width: Theme.Spacing.xxs)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityLabel(count.map { $0 > 0 ? "\(title), \($0) terminals" : title } ?? title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func nameColor(isActive: Bool, isHovering: Bool) -> Color {
        if isActive { return Theme.accentPrimary }
        return isHovering ? Theme.textPrimary : Theme.textSecondary
    }
}

#if DEBUG
#Preview("TasksPanelItem") {
    TasksPanelItem()
        .frame(width: 280)
        .background(Theme.bgSurface)
        .environment(\.shell, ShellContext.preview())
}
#endif
