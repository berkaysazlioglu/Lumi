import SwiftUI
import LumiMobileKit

/// Shared metrics of the Apple Projects rows.
enum AppleProjectsMetrics {
    /// Width of the leading icon column (checkout symbol, provider artwork),
    /// so titles line up the way `Label` lines them up.
    static let iconColumn: CGFloat = 28
    /// Agents step in by one icon column under their checkout / folder.
    static let childIndent: CGFloat = iconColumn
    static let providerIconSize: CGFloat = 20
    /// Project badge (Reminders' "My Lists" icon): a filled circle with a white glyph.
    static let projectBadgeSize: CGFloat = 26
    static let projectGlyphScale: CGFloat = 0.5
    static let projectEmojiScale: CGFloat = 0.7
    static let rowSpacing: CGFloat = 12
    static let subtitleSpacing: CGFloat = 2
}

// MARK: - Project header

/// Section header of a project: its colored badge and name.
struct AppleProjectHeader: View {
    let node: ProjectNode
    /// Agents hidden while the section is collapsed (shown as a count).
    let collapsedCount: Int?

    var body: some View {
        HStack(spacing: AppleProjectsMetrics.rowSpacing) {
            AppleProjectBadge(appearance: node.appearance)
            Text(node.name).lineLimit(1)
            Spacer(minLength: 0)
            if let collapsedCount, collapsedCount > 0 {
                Text("\(collapsedCount)")
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

/// A project's identity (Mac decision 120) the Reminders way: its SF Symbol
/// white on a circle of its color, or its emoji on a soft fill.
struct AppleProjectBadge: View {
    let appearance: ProjectAppearance

    private var size: CGFloat { AppleProjectsMetrics.projectBadgeSize }

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
        AppleSymbolBadge(symbol: name, color: Self.color(appearance.color))
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

    private var size: CGFloat { AppleProjectsMetrics.projectBadgeSize }

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

    private var title: String { checkoutDisplayTitle(checkout.node, in: project) }
    private var branch: String? { checkout.node.branch.flatMap { $0.isEmpty ? nil : $0 } }
    private var symbol: String { checkout.node.kind == "workspace" ? "arrow.triangle.branch" : "house" }

    var body: some View {
        HStack(spacing: AppleProjectsMetrics.rowSpacing) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: AppleProjectsMetrics.iconColumn)
            VStack(alignment: .leading, spacing: AppleProjectsMetrics.subtitleSpacing) {
                Text(title).font(.body.weight(.medium)).lineLimit(1)
                if let branch, branch != title {
                    Text(branch)
                        .font(.footnote).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            AppleStartMenu(path: checkout.node.path, actions: actions,
                           accessibilityLabel: "New agent on \(branch ?? title)") {
                startItems
            }
        }
        .contextMenu { startItems }
    }

    @ViewBuilder private var startItems: some View {
        Button { actions.start(checkout.node.path) } label: {
            Label("New Claude on \(branch ?? title)", systemImage: "plus.bubble")
        }
        // Same guard as the `+`: one start in flight at a time (AppModel can't
        // tell two concurrent start results apart).
        .disabled(!actions.isOnline || actions.startingPath != nil)
        Button { actions.newBranch(project.path, branch ?? "") } label: {
            Label("New Branch from \(branch ?? "Current")…", systemImage: "arrow.triangle.branch")
        }
        .disabled(!actions.isOnline || actions.startingPath != nil)
    }
}

/// Trailing `+` of a start row: tap starts a Claude at `path`, long-press opens
/// `items`; a spinner while that start is in flight.
struct AppleStartMenu<Items: View>: View {
    let path: String
    let actions: ProjectsListActions
    let accessibilityLabel: String
    @ViewBuilder let items: () -> Items

    var body: some View {
        if actions.startingPath == path {
            ProgressView()
        } else {
            Menu {
                items()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
            } primaryAction: {
                actions.start(path)
            }
            .buttonStyle(.borderless)
            .disabled(!actions.isOnline || actions.startingPath != nil)
            .accessibilityLabel(accessibilityLabel)
        }
    }
}

// MARK: - Agent

/// An agent, Mail-style: provider artwork, title over its status, relative
/// time and a disclosure chevron. Attention (finished unseen / needs input)
/// reads like an unread message — bold title, tinted status.
struct AppleAgentRow: View {
    let agent: AgentRowData
    let actions: ProjectsListActions

    var body: some View {
        Button { actions.open(agent.id) } label: { label }
            .padding(.leading, AppleProjectsMetrics.childIndent)
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + AppleProjectsMetrics.childIndent }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { actions.delete(agent.id) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .contextMenu {
                Button { actions.open(agent.id) } label: { Label("Open", systemImage: "arrow.up.forward.app") }
                Button(role: .destructive) { actions.delete(agent.id) } label: {
                    Label("Delete Chat", systemImage: "trash")
                }
            }
    }

    private var label: some View {
        HStack(spacing: AppleProjectsMetrics.rowSpacing) {
            UsageProviderIcon(id: agent.provider, size: AppleProjectsMetrics.providerIconSize)
                .frame(width: AppleProjectsMetrics.iconColumn)
            VStack(alignment: .leading, spacing: AppleProjectsMetrics.subtitleSpacing) {
                Text(agent.title)
                    .fontWeight(agent.needsAttention ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                status
            }
            Spacer(minLength: 0)
            Text(PhoneRelativeTime.shortLabel(agent.lastActivityAt, now: Date().timeIntervalSince1970 * 1000))
                .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var status: some View {
        HStack(spacing: AppleProjectsMetrics.subtitleSpacing * 2) {
            AgentActivityGlyph(activity: agent.activity)
            Text(agent.activity.title)
                .font(.subheadline)
                .foregroundStyle(statusColor)
        }
    }

    private var statusColor: AnyShapeStyle {
        switch agent.activity {
        case .awaitingDecision: AnyShapeStyle(.orange)
        case .failed: AnyShapeStyle(.red)
        default: agent.needsAttention ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
        }
    }
}
