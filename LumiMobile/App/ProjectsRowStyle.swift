import SwiftUI

/// Settings ▸ Row Size for the Projects list (agent + checkout rows).
enum ProjectsRowSize: String, CaseIterable, Identifiable {
    case small, medium, large

    static let storageKey = "projectsRowSize"
    static let `default` = ProjectsRowSize.medium

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var agentFont: Font {
        switch self {
        case .small: .footnote
        case .medium: .subheadline
        case .large: .body
        }
    }

    var checkoutFont: Font {
        switch self {
        case .small: .caption.weight(.semibold)
        case .medium: .footnote.weight(.semibold)
        case .large: .subheadline.weight(.semibold)
        }
    }

    /// Provider icon in agent rows.
    var iconSize: CGFloat {
        switch self {
        case .small: 12
        case .medium: 14
        case .large: 17
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .small: 3
        case .medium: 6
        case .large: 9
        }
    }
}

/// Row Size × the test scale (A− / A+ under the usage strip) → concrete
/// fonts and spacing. Point sizes mirror the text styles the sizes used
/// (footnote 13 / subheadline 15 / body 17) so scale 1 looks as before.
struct ProjectsRowMetrics {
    let size: ProjectsRowSize
    let scale: CGFloat

    static let scaleKey = "projectsRowScale"
    static let scaleStep = 0.1
    static let scaleRange: ClosedRange<Double> = 0.8...1.6
    private static let projectFontSize: CGFloat = 17
    private static let projectPadding: CGFloat = 9

    private var agentPoints: CGFloat {
        switch size {
        case .small: 13
        case .medium: 15
        case .large: 17
        }
    }

    var agentFont: Font { .system(size: agentPoints * scale) }
    var checkoutFont: Font { .system(size: (agentPoints - 2) * scale, weight: .semibold) }
    var projectFont: Font { .system(size: Self.projectFontSize * scale, weight: .semibold) }
    var detailFont: Font { .system(size: (agentPoints - 3) * scale) }
    var iconSize: CGFloat { size.iconSize * scale }
    var verticalPadding: CGFloat { size.verticalPadding * scale }
    var projectPadding: CGFloat { Self.projectPadding * scale }
}

/// Depth in the Projects tree: project → checkout / Other folder → agent.
enum ProjectsTreeLevel: Int {
    case project, checkout, agent

    /// Each level steps in so a row reads as the child of the one above.
    static let indentStep: CGFloat = 14
    var indent: CGFloat { CGFloat(rawValue) * Self.indentStep }
}

private struct ProjectsTreeRow: ViewModifier {
    let level: ProjectsTreeLevel
    let verticalPadding: CGFloat
    /// Project color washed over the row (test toggle) — stronger on the
    /// project band, fading towards agents so the group still reads as a tree.
    let tint: Color?

    private static let horizontalInset: CGFloat = 16
    private static let trailingInset: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(.leading, level.indent)
            .padding(.vertical, verticalPadding)
            // Separator starts where the row's content starts — the indent stays legible.
            .alignmentGuide(.listRowSeparatorLeading) { _ in level.indent }
            .listRowInsets(EdgeInsets(top: 0, leading: Self.horizontalInset,
                                      bottom: 0, trailing: Self.trailingInset))
            // Project rows are a band (Mac panel section header); the rest sit on the surface.
            .listRowBackground(background)
            .listRowSeparator(.visible)
            .listRowSeparatorTint(LumiPalette.border)
    }

    private var background: some View {
        ZStack {
            level == .project ? LumiPalette.elevated : LumiPalette.background
            if let tint { tint.opacity(Self.tintOpacity[level.rawValue]) }
        }
    }

    /// project / checkout / agent.
    private static let tintOpacity: [Double] = [0.22, 0.12, 0.07]
}

extension View {
    func treeRow(_ level: ProjectsTreeLevel, verticalPadding: CGFloat, tint: Color? = nil) -> some View {
        modifier(ProjectsTreeRow(level: level, verticalPadding: verticalPadding, tint: tint))
    }
}

/// Fold/unfold of a project group: quick, not instant.
enum ProjectsMotion {
    static let fold = Animation.easeInOut(duration: 0.25)
}
