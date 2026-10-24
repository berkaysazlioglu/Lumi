import SwiftUI
import LumiMobileKit
import LumiWire

/// Shared metrics of the Apple Projects rows (compact: one text line per row).
enum AppleProjectsMetrics {
    /// Width of the leading icon column (checkout symbol, provider artwork),
    /// so titles line up the way `Label` lines them up.
    static let iconColumn: CGFloat = 22
    /// Agents step in by one icon column under their checkout / folder.
    static let childIndent: CGFloat = iconColumn
    static let providerIconSize: CGFloat = 15
    /// Project badge (Reminders' "My Lists" icon): a filled circle with a white glyph.
    static let projectBadgeSize: CGFloat = 22
    static let projectGlyphScale: CGFloat = 0.5
    static let projectEmojiScale: CGFloat = 0.7
    static let rowSpacing: CGFloat = 10
    static let subtitleSpacing: CGFloat = 2
    static let minRowHeight: CGFloat = 34
    static let rowInsets = EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)
    static let titleFont = Font.subheadline
    static let detailFont = Font.caption
    /// The project band: its color washed over the card surface.
    static let bandOpacity = 0.22
    /// Group Color test toggle: the project color fading over its checkouts / agents.
    static let checkoutTintOpacity = 0.12
    static let agentTintOpacity = 0.07
    /// Outline of the project header a dragged project hovers (decision 132),
    /// inset and rounded so the card's own rounded clip doesn't cut its corners.
    static let dropTargetLineWidth: CGFloat = 2
    static let dropTargetInset: CGFloat = 3
    /// At least the card's corner radius (~11pt) minus the inset, with headroom.
    static let dropTargetRadius: CGFloat = 12
    private static let titlePoints: CGFloat = 15   // .subheadline
    private static let detailPoints: CGFloat = 12  // .caption

    /// Fonts under the A− / A+ test scale (scale 1 = the text styles above).
    static func titleFont(_ scale: CGFloat) -> Font { .system(size: titlePoints * scale) }
    static func detailFont(_ scale: CGFloat) -> Font { .system(size: detailPoints * scale) }
}

extension View {
    /// Row surface, optionally washed with the project color (Group Color test toggle).
    func appleRowBackground(tint: Color?, opacity: Double) -> some View {
        listRowBackground(ZStack {
            Color(.secondarySystemGroupedBackground)
            if let tint { tint.opacity(opacity) }
        })
    }
}

extension View {
    /// Compact insets shared by every Apple Projects row.
    /// `scale` (A− / A+ test control) grows the whole row — insets too —
    /// not only its text, so every step makes the row itself bigger.
    func appleProjectsRow(scale: CGFloat = 1) -> some View {
        let insets = AppleProjectsMetrics.rowInsets
        return listRowInsets(EdgeInsets(top: insets.top * scale, leading: insets.leading,
                                        bottom: insets.bottom * scale, trailing: insets.trailing))
    }
}

// MARK: - Group header

/// First row of a project (or `Other`) card: badge and name on a band of the
/// project's color, so the card reads as one group. Tap collapses the card;
/// collapsed, it shows how many agents it hides.
struct AppleGroupHeaderRow<Title: View>: View {
    let tint: Color
    @AppStorage(ProjectsRowMetrics.scaleKey) private var scale = 1.0
    @Binding var isExpanded: Bool
    let collapsedCount: Int
    /// A dragged project hovers over this one (decision 132 reorder).
    var isDropTarget = false
    /// Projects get a trailing `⋯` menu with Edit Project… (decision 132); `Other` doesn't.
    var onEdit: (() -> Void)?
    var isEditEnabled = true
    @ViewBuilder let title: () -> Title

    var body: some View {
        HStack(spacing: AppleProjectsMetrics.rowSpacing) {
            Button {
                // The binding's setter animates the fold (ProjectsMotion.fold).
                isExpanded.toggle()
            } label: {
                HStack(spacing: AppleProjectsMetrics.rowSpacing) {
                    title()
                        .font(AppleProjectsMetrics.titleFont(scale).weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if !isExpanded && collapsedCount > 0 {
                        Text("\(collapsedCount)")
                            .font(AppleProjectsMetrics.detailFont(scale)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            if let onEdit { editMenu(onEdit) }
        }
        .appleProjectsRow(scale: scale)
        .listRowBackground(band)
    }

    private func editMenu(_ onEdit: @escaping () -> Void) -> some View {
        Menu {
            Button(action: onEdit) { Label("Edit Project…", systemImage: "paintpalette") }
                .disabled(!isEditEnabled)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(AppleProjectsMetrics.titleFont(scale))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Project Actions")
    }

    private var band: some View {
        ZStack {
            Color(.secondarySystemGroupedBackground)
            tint.opacity(AppleProjectsMetrics.bandOpacity)
            if isDropTarget {
                Color.accentColor.opacity(AppleProjectsMetrics.bandOpacity)
                RoundedRectangle(cornerRadius: AppleProjectsMetrics.dropTargetRadius, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: AppleProjectsMetrics.dropTargetLineWidth)
                    .padding(AppleProjectsMetrics.dropTargetInset)
            }
        }
    }
}

/// A project's identity (Mac decision 120) the Reminders way: its SF Symbol
/// white on a circle of its color, or its emoji on a soft fill.
struct AppleProjectBadge: View {
    let appearance: ProjectAppearance
    /// Unscaled diameter; the A− / A+ scale applies on top.
    var baseSize = AppleProjectsMetrics.projectBadgeSize

    @AppStorage(ProjectsRowMetrics.scaleKey) private var scale = 1.0
    private var size: CGFloat { baseSize * scale }

    var body: some View {
        switch appearance.icon {
        case let .emoji(value)?:
            Text(value)
                .font(.system(size: size * AppleProjectsMetrics.projectEmojiScale))
                .frame(width: size, height: size)
                .background(Color(.tertiarySystemFill), in: Circle())
        case let .symbol(name)?:
            symbol(name)
        case nil:
            symbol(ProjectIconView.defaultSymbol)
        }
    }

    private func symbol(_ name: String) -> some View {
        AppleSymbolBadge(symbol: name, color: Self.color(appearance.color), baseSize: baseSize)
    }

    /// Mac palette mapped onto the closest system colors (they adapt to dark mode).
    static func color(_ id: ProjectColorID?) -> Color {
        switch id {
        case .blue: .blue
        case .teal: .teal
        case .pink: .pink
        case .orange: .orange
        case .lime: .green
        case .green: .mint
        case .fuchsia: .purple
        case nil: Color(.systemGray)
        }
    }
}

/// White SF Symbol on a filled circle — the project badge, also used by `Other`.
struct AppleSymbolBadge: View {
    let symbol: String
    let color: Color
    var baseSize = AppleProjectsMetrics.projectBadgeSize

    @AppStorage(ProjectsRowMetrics.scaleKey) private var scale = 1.0
    private var size: CGFloat { baseSize * scale }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * AppleProjectsMetrics.projectGlyphScale, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
    }
}

// MARK: - Checkout

/// A checkout of a project: house (root) or branch symbol, its title and,
/// when it differs, its branch; trailing `+` starts a Claude there.
struct AppleCheckoutRow: View {
    let checkout: CheckoutRowData
    let project: ProjectNode
    let actions: ProjectsListActions
    /// Project color for the Group Color test toggle.
    var tint: Color?
    @AppStorage(ProjectsRowMetrics.scaleKey) private var scale = 1.0

    private var title: String { checkoutDisplayTitle(checkout.node, in: project) }
    private var branch: String? { checkout.node.branch.flatMap { $0.isEmpty ? nil : $0 } }
    private var symbol: String { checkout.node.kind == "workspace" ? "arrow.triangle.branch" : "house" }

    var body: some View {
        HStack(spacing: AppleProjectsMetrics.rowSpacing) {
            Image(systemName: symbol)
                .font(AppleProjectsMetrics.titleFont(scale))
                .foregroundStyle(.secondary)
                .frame(width: AppleProjectsMetrics.iconColumn * scale)
            Text(title).font(AppleProjectsMetrics.titleFont(scale).weight(.medium)).lineLimit(1)
                .layoutPriority(1)
            if let branch, branch != title {
                Text(branch)
                    .font(AppleProjectsMetrics.detailFont(scale)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
            AppleStartMenu(path: checkout.node.path, actions: actions,
                           accessibilityLabel: "New agent on \(branch ?? title)") {
                newBranchItem
            }
        }
        .appleProjectsRow(scale: scale)
        .appleRowBackground(tint: tint, opacity: AppleProjectsMetrics.checkoutTintOpacity)
        .contextMenu {
            Button { actions.start(checkout.node.path, nil) } label: {
                Label("New Claude on \(branch ?? title)", systemImage: "plus.bubble")
            }
            // Same guard as the `+`: one start in flight at a time (AppModel can't
            // tell two concurrent start results apart).
            .disabled(!actions.isOnline || actions.startingPath != nil)
            newBranchItem
        }
    }

    private var newBranchItem: some View {
        Button { actions.newBranch(project.path, branch ?? "") } label: {
            Label("New Branch from \(branch ?? "Current")…", systemImage: "arrow.triangle.branch")
        }
        .disabled(!actions.isOnline || actions.startingPath != nil)
    }
}

/// Trailing `+` of a start row (decision 133): tap opens the Mac's New Claude
/// menu — Claude, then Codex / Bash (not on the phone yet, shown disabled), a
/// separator and Claude's model shortcuts (Mac decision 121; Settings ▸ Claude
/// Models, off by default), then the row's own `extras`. A spinner while that start is in flight.
struct AppleStartMenu<Extras: View>: View {
    let path: String
    let actions: ProjectsListActions
    let accessibilityLabel: String
    @ViewBuilder var extras: () -> Extras
    @AppStorage(ClaudeModelShortcuts.storageKey) private var showsModels = ClaudeModelShortcuts.defaultValue

    var body: some View {
        if actions.startingPath == path {
            ProgressView()
        } else {
            Menu {
                Section {
                    Button { actions.start(path, nil) } label: { Label("Claude", image: "ProviderClaude") }
                    Button {} label: { Label("Codex", image: "ProviderCodex") }.disabled(true)
                    Button {} label: { Label("Bash", systemImage: "terminal") }.disabled(true)
                }
                if showsModels {
                    Section {
                        ForEach(ClaudeModelAlias.allCases, id: \.self) { alias in
                            Button { actions.start(path, alias) } label: {
                                Label("Claude \(alias.displayName)", image: "ProviderClaude")
                            }
                        }
                    }
                }
                Section { extras() }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
            }
            .menuOrder(.fixed)
            .buttonStyle(.borderless)
            .disabled(!actions.isOnline || actions.startingPath != nil)
            .accessibilityLabel(accessibilityLabel)
        }
    }
}

extension AppleStartMenu where Extras == EmptyView {
    init(path: String, actions: ProjectsListActions, accessibilityLabel: String) {
        self.init(path: path, actions: actions, accessibilityLabel: accessibilityLabel) { EmptyView() }
    }
}

// MARK: - Agent

/// An agent on one line: provider artwork, title, status glyph, relative time
/// and a disclosure chevron. Attention (finished unseen / needs input) reads
/// like an unread message — bold title.
struct AppleAgentRow: View {
    let agent: AgentRowData
    let actions: ProjectsListActions
    /// Project color for the Group Color test toggle.
    var tint: Color?
    @AppStorage(ProjectsRowMetrics.scaleKey) private var scale = 1.0
    @State private var confirmingDelete = false

    var body: some View {
        Button { actions.open(agent.id) } label: { label }
            .padding(.leading, AppleProjectsMetrics.childIndent)
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + AppleProjectsMetrics.childIndent }
            .appleProjectsRow(scale: scale)
            .appleRowBackground(tint: tint, opacity: AppleProjectsMetrics.agentTintOpacity)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .contextMenu {
                Button { actions.open(agent.id) } label: { Label("Open", systemImage: "arrow.up.forward.app") }
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label("Delete Chat", systemImage: "trash")
                }
            }
            .confirmDeleteChat(isPresented: $confirmingDelete, title: agent.title) { actions.delete(agent.id) }
    }

    private var label: some View {
        HStack(spacing: AppleProjectsMetrics.rowSpacing) {
            UsageProviderIcon(id: agent.provider, size: AppleProjectsMetrics.providerIconSize * scale)
                .frame(width: AppleProjectsMetrics.iconColumn * scale)
            Text(agent.title)
                .font(AppleProjectsMetrics.titleFont(scale))
                .fontWeight(agent.needsAttention ? .semibold : .regular)
                .foregroundStyle(titleColor)
                .lineLimit(1)
            Spacer(minLength: 0)
            AgentActivityGlyph(activity: agent.activity)
            Text(PhoneRelativeTime.shortLabel(agent.lastActivityAt, now: Date().timeIntervalSince1970 * 1000))
                .font(AppleProjectsMetrics.detailFont(scale)).foregroundStyle(.secondary).monospacedDigit()
            Image(systemName: "chevron.forward")
                .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    /// Decision and failure tint the title — the status line is gone in the compact row.
    /// Concrete colors: a hierarchical `.primary` inside a list `Button` resolves to the tint.
    private var titleColor: Color {
        switch agent.activity {
        case .awaitingDecision: .orange
        case .failed: .red
        default: .primary
        }
    }
}
