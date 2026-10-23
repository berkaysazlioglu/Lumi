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

    var verticalPadding: CGFloat {
        switch self {
        case .small: 3
        case .medium: 6
        case .large: 9
        }
    }
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
            .listRowBackground(level == .project ? LumiPalette.elevated : LumiPalette.background)
            .listRowSeparator(.visible)
            .listRowSeparatorTint(LumiPalette.border)
    }
}

extension View {
    func treeRow(_ level: ProjectsTreeLevel, verticalPadding: CGFloat) -> some View {
        modifier(ProjectsTreeRow(level: level, verticalPadding: verticalPadding))
    }
}
