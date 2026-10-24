import SwiftUI
import LumiMobileKit

/// Top of the Projects list: the Mac's usage chips, then the look controls,
/// as one block with breathing room between the two lines.
struct ProjectsListHeader: View {
    let usage: UsageReport?
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ProjectsHeaderChip.lineSpacing) {
            if usage?.isEmpty == false {
                ProjectsUsageStrip(report: usage, isStale: isStale)
            }
            ProjectsLookControls()
        }
    }
}

/// Temporary test controls (to be removed once the look is decided): wash the
/// project color over its whole group, and step the Projects text size.
struct ProjectsLookControls: View {
    static let tintKey = "projectsTintsGroups"

    @AppStorage(tintKey) private var tintsGroups = false
    @AppStorage(ProjectsRowMetrics.scaleKey) private var rowScale = 1.0

    private static let percentWidth: CGFloat = 44
    private static let epsilon = 0.001

    var body: some View {
        HStack(spacing: ProjectsHeaderChip.spacing) {
            groupColorToggle
            Spacer(minLength: 0)
            textSizeStepper
        }
    }

    private var groupColorToggle: some View {
        Button { tintsGroups.toggle() } label: {
            HStack(spacing: ProjectsHeaderChip.iconSpacing) {
                Image(systemName: tintsGroups ? "paintpalette.fill" : "paintpalette")
                Text("Group Color")
            }
                .font(ProjectsHeaderChip.font)
                .foregroundStyle(tintsGroups ? Color.accentColor : Color.primary)
                .padding(.horizontal, ProjectsHeaderChip.horizontalPadding)
                .headerChip(isActive: tintsGroups)
        }
        .buttonStyle(.borderless)
        .accessibilityValue(tintsGroups ? "On" : "Off")
    }

    /// A− | 100% | A+ as one segmented chip.
    private var textSizeStepper: some View {
        HStack(spacing: 0) {
            stepButton("textformat.size.smaller", label: "Smaller Text", direction: -1)
                .disabled(rowScale <= ProjectsRowMetrics.scaleRange.lowerBound + Self.epsilon)
            Divider().padding(.vertical, ProjectsHeaderChip.dividerInset)
            Text("\(Int((rowScale * 100).rounded()))%")
                .font(ProjectsHeaderChip.font.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: Self.percentWidth)
            Divider().padding(.vertical, ProjectsHeaderChip.dividerInset)
            stepButton("textformat.size.larger", label: "Larger Text", direction: 1)
                .disabled(rowScale >= ProjectsRowMetrics.scaleRange.upperBound - Self.epsilon)
        }
        .headerChip(isActive: false)
    }

    private func stepButton(_ symbol: String, label: String, direction: Double) -> some View {
        Button { step(direction) } label: {
            Image(systemName: symbol)
                .font(ProjectsHeaderChip.font)
                .frame(width: ProjectsHeaderChip.height, height: ProjectsHeaderChip.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
    }

    private func step(_ direction: Double) {
        let next = rowScale + direction * ProjectsRowMetrics.scaleStep
        let range = ProjectsRowMetrics.scaleRange
        rowScale = (min(max(next, range.lowerBound), range.upperBound) * 10).rounded() / 10
    }
}

/// One look for every chip in the Projects header (usage, Group Color, text size):
/// the system's borderless fill capsule, like the list around it — same height,
/// so the two lines read as one block.
enum ProjectsHeaderChip {
    static let height: CGFloat = 30
    static let horizontalPadding: CGFloat = 12
    static let spacing: CGFloat = 8
    static let iconSpacing: CGFloat = 5
    /// Between the usage line and the controls line.
    static let lineSpacing: CGFloat = 10
    static let dividerInset: CGFloat = 8
    static let font = Font.caption.weight(.semibold)
    static let activeFillOpacity = 0.18
}

private struct HeaderChipBackground: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .frame(minHeight: ProjectsHeaderChip.height)
            .background(isActive ? AnyShapeStyle(Color.accentColor.opacity(ProjectsHeaderChip.activeFillOpacity))
                                 : AnyShapeStyle(Color(.tertiarySystemFill)),
                        in: Capsule())
    }
}

extension View {
    func headerChip(isActive: Bool) -> some View {
        modifier(HeaderChipBackground(isActive: isActive))
    }
}
