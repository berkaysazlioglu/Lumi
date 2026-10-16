import LumiKit
import SwiftUI

/// Proje kimlik renginin noktası (karar 120): Projects satırı ve görünüm
/// modalı. `nil` → boş halka ("renk yok").
struct ProjectColorDot: View {
    let color: Color?
    var size: CGFloat = Theme.ProjectTint.dotSize

    var body: some View {
        Group {
            if let color {
                Circle().fill(color)
            } else {
                Circle().strokeBorder(Theme.textMuted, lineWidth: Theme.Stroke.hairline)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Kök checkout ikonu (karar 120): SF Symbol ya da emoji, aynı punto.
struct ProjectIconView: View {
    let icon: ProjectIcon
    var size: Theme.Typography.Size = .label
    var color: Color = Theme.textMuted

    var body: some View {
        Group {
            switch icon {
            case .symbol(let name):
                Image(systemName: name)
                    .font(Theme.Typography.ui(size))
                    .foregroundStyle(color)
            case .emoji(let value):
                Text(value)
                    .font(Theme.Typography.ui(size))
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("ProjectAppearanceViews") {
    HStack(spacing: Theme.Spacing.md) {
        ProjectColorDot(color: Theme.projectColor(.teal))
        ProjectColorDot(color: nil)
        ProjectIconView(icon: .default)
        ProjectIconView(icon: .symbol("gamecontroller"))
        ProjectIconView(icon: .emoji("🚀"))
    }
    .padding(Theme.Spacing.xxl)
    .background(Theme.bgSurface)
}
#endif
