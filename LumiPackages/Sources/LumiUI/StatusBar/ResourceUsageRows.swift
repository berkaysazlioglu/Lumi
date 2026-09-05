import LumiKit
import LumiState
import SwiftUI

/// Resource Manager listesinin kolon ölçüleri (Orca `w-12` / `w-16` / `w-5`):
/// her satır ve başlık aynı sağ oluğu ayırır ki CPU/RSS kolonları kill
/// düğmesi olsun olmasın hizalı kalsın.
enum ResourceUsageColumns {
    static let cpu: CGFloat = 48
    static let memory: CGFloat = 64
    static let trailingGutter: CGFloat = 20
    static let sparklineWidth: CGFloat = 48
    static let sparklineHeight: CGFloat = 14
    /// Oturum satırı sol girintisi (Orca `pl-10`).
    static let sessionIndent: CGFloat = 40
}

/// CPU + RSS çifti; `nil` ölçüm "—" olarak soluk çizilir.
struct ResourceMetricPair: View {
    let metrics: ResourceMetrics?
    var size: Theme.Typography.Size = .body

    var body: some View {
        HStack(spacing: 0) {
            Text(metrics.map { ResourceUsageFormat.cpu($0.cpuPercent) } ?? "—")
                .frame(width: ResourceUsageColumns.cpu, alignment: .trailing)
            Text(metrics.map { ResourceUsageFormat.memory($0.residentBytes) } ?? "—")
                .frame(width: ResourceUsageColumns.memory, alignment: .trailing)
        }
        .font(Theme.Typography.ui(size))
        .monospacedDigit()
        .foregroundStyle(metrics == nil ? Theme.textMuted.opacity(Self.mutedOpacity) : Theme.textMuted)
        .lineLimit(1)
    }

    private static let mutedOpacity = 0.5
}

/// Sağ oluk: kill düğmesi ya da boş yer tutucu.
struct ResourceTrailingGutter<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack { content() }
            .frame(width: ResourceUsageColumns.trailingGutter, alignment: .trailing)
    }
}

/// Uygulama RSS geçmişi (Orca `Sparkline`): 48×14, min-max normalize.
struct ResourceSparkline: View {
    let samples: [Double]

    var body: some View {
        Canvas { context, size in
            var path = Path()
            guard samples.count >= 2, let min = samples.min(), let max = samples.max() else {
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(path, with: .color(Theme.textMuted.opacity(Self.strokeOpacity)), lineWidth: Theme.Stroke.hairline)
                return
            }
            let range = max - min == 0 ? 1 : max - min
            let stepX = size.width / CGFloat(samples.count - 1)
            for (index, sample) in samples.enumerated() {
                let point = CGPoint(
                    x: CGFloat(index) * stepX,
                    y: size.height - CGFloat((sample - min) / range) * size.height
                )
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(
                path, with: .color(Theme.textMuted.opacity(Self.strokeOpacity)),
                style: StrokeStyle(lineWidth: Theme.Stroke.hairline, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: ResourceUsageColumns.sparklineWidth, height: ResourceUsageColumns.sparklineHeight)
        .accessibilityHidden(true)
    }

    private static let strokeOpacity = 0.7
}

/// Repo grubu başlığı: chevron + BÜYÜK HARF ad + metrikler.
struct ResourceRepoGroupRow: View {
    let group: ResourceUsageStore.RepoGroup
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(Theme.Typography.ui(.caption, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: Theme.Row.iconColumn)
                    .accessibilityHidden(true)
                Text(group.name.uppercased())
                    .font(Theme.Typography.ui(.label, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                ResourceMetricPair(metrics: group.metrics)
                ResourceTrailingGutter {}
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Row.control)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverButtonStyle(background: .clear, hoverBackground: Theme.bgElevated, cornerRadius: Theme.Radius.none))
        .accessibilityLabel("\(isCollapsed ? "Expand" : "Collapse") repo \(group.name)")
    }
}

/// Oturum satırı: durum noktası, başlık, metrikler, hover'da kill (Orca `SessionRow`).
struct ResourceSessionRow: View {
    let session: ResourceUsageStore.SessionRow
    let onNavigate: () -> Void
    let onKill: () -> Void

    var body: some View {
        HoverReader { hovering in
            HStack(spacing: Theme.Spacing.sm) {
                Button(action: onNavigate) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Circle()
                            .fill(dotColor)
                            .frame(width: StatusBarMetrics.dotSize, height: StatusBarMetrics.dotSize)
                            .accessibilityHidden(true)
                        Text(session.title)
                            .font(Theme.Typography.ui(.label))
                            .foregroundStyle(Theme.textMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                        ResourceMetricPair(metrics: session.metrics, size: .label)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Focus session \(session.title)")
                ResourceTrailingGutter {
                    IconButton(systemName: "xmark", label: "Kill session \(session.title)", size: .caption, role: .destructive, action: onKill)
                        .opacity(hovering ? 1 : 0)
                }
            }
            .padding(.leading, ResourceUsageColumns.sessionIndent)
            .padding(.trailing, Theme.Spacing.md)
            .frame(height: Theme.Row.control)
            .background(hovering ? Theme.bgElevated.opacity(Self.hoverOpacity) : .clear)
        }
    }

    private var dotColor: Color {
        switch session.status {
        case .working: return Theme.success
        case .waitingUnseen, .waitingFocused, .waitingSeen: return Theme.warning
        case .error: return Theme.error
        case .idle: return Theme.textMuted.opacity(Self.idleOpacity)
        }
    }

    private static let hoverOpacity = 0.6
    private static let idleOpacity = 0.4
}

/// Uygulamanın kendi bölümü (Orca `AppSection`): "LUMI" + sparkline + metrikler;
/// açıkken Main / Helpers alt satırları.
struct ResourceAppSection: View {
    let app: AppResourceUsage
    let history: [Double]
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
            Button(action: onToggle) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(Theme.Typography.ui(.caption, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: Theme.Row.iconColumn)
                        .accessibilityHidden(true)
                    Text("Lumi".uppercased())
                        .font(Theme.Typography.ui(.label, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.textMuted)
                    Spacer(minLength: 0)
                    ResourceSparkline(samples: history)
                    ResourceMetricPair(metrics: app.total)
                    ResourceTrailingGutter {}
                }
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: Theme.Row.control)
                .contentShape(Rectangle())
            }
            .buttonStyle(HoverButtonStyle(background: .clear, hoverBackground: Theme.bgElevated, cornerRadius: Theme.Radius.none))
            .accessibilityLabel("\(isCollapsed ? "Expand" : "Collapse") Lumi")
            if !isCollapsed {
                subRow("Main", metrics: app.main)
                if app.helpers.cpuPercent > 0 || app.helpers.residentBytes > 0 {
                    subRow("Helpers", metrics: app.helpers)
                }
            }
        }
    }

    private func subRow(_ label: String, metrics: ResourceMetrics) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(label)
                .font(Theme.Typography.ui(.label))
                .foregroundStyle(Theme.textMuted)
            Spacer(minLength: 0)
            ResourceMetricPair(metrics: metrics, size: .label)
            ResourceTrailingGutter {}
        }
        .padding(.leading, Theme.Spacing.xxl)
        .padding(.trailing, Theme.Spacing.md)
        .frame(height: Theme.Row.compact + Theme.Spacing.xs)
    }
}

/// Kolon başlığı: Name · CPU · RSS — hepsi sıralama düğmesi.
struct ResourceColumnHeader: View {
    @Binding var sort: ResourceUsageStore.SortOption

    var body: some View {
        HStack(spacing: 0) {
            sortButton("Name", option: .name)
                .frame(maxWidth: .infinity, alignment: .leading)
            sortButton("CPU", option: .cpu)
                .frame(width: ResourceUsageColumns.cpu, alignment: .trailing)
            sortButton("RSS", option: .memory)
                .frame(width: ResourceUsageColumns.memory, alignment: .trailing)
            ResourceTrailingGutter {}
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Row.compact)
        .background(Theme.bgDeep.opacity(Self.headerOpacity))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
        }
    }

    private func sortButton(_ title: String, option: ResourceUsageStore.SortOption) -> some View {
        let isActive = sort == option
        return Button { sort = option } label: {
            Text(title.uppercased())
                .font(Theme.Typography.ui(.caption, weight: isActive ? .semibold : .regular))
                .tracking(0.6)
                .foregroundStyle(isActive ? Theme.textPrimary : Theme.textMuted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(title)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private static let headerOpacity = 0.5
}
