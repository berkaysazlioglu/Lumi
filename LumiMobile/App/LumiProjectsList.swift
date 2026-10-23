import SwiftUI
import LumiMobileKit

/// The Lumi-styled Projects tree (Mac panel parity, decisions 127–128): project
/// bands, indented checkouts and agents, separators, Row Size.
struct LumiProjectsList: View {
    let model: AppModel
    let actions: ProjectsListActions

    @State private var collapsedProjects: Set<String> = []
    @AppStorage(ProjectsRowSize.storageKey) private var rowSize = ProjectsRowSize.default
    // Test controls under the usage strip (to be removed once decided).
    @AppStorage(ProjectsRowMetrics.scaleKey) private var rowScale = 1.0
    @AppStorage(ProjectsDebugControls.tintKey) private var tintsGroups = false

    private var metrics: ProjectsRowMetrics { ProjectsRowMetrics(size: rowSize, scale: rowScale) }

    var body: some View {
        List {
            ProjectsUsageStrip(report: model.usage, isStale: !model.macOnline)
                .lumiRow()
            ProjectsDebugControls()
                .lumiRow()
            Text("Projects")
                .font(.largeTitle.bold())
                .foregroundStyle(LumiPalette.textPrimary)
                .lumiRow()
            if !model.macOnline { offlineBanner }
            let others = model.otherGroups
            let locations = looseStartLocations(model.projectsSnapshot)
            if model.projectTree.isEmpty { emptyState }
            ForEach(model.projectTree) { project in
                projectSection(project)
            }
            if !others.isEmpty || !locations.isEmpty { otherSection(others, locations: locations) }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)
        .background(LumiPalette.background)
    }

    // MARK: - Rows

    @ViewBuilder
    private func projectSection(_ project: ProjectRowData) -> some View {
        let collapsed = collapsedProjects.contains(project.id)
        // The header is a plain row (not a Section header): plain-list headers
        // carry their own system fill that ignores the Lumi surface.
        sectionHeader(id: project.id, collapsed: collapsed) {
            ProjectIconView(icon: project.node.appearance.icon)
            Text(project.node.name).font(metrics.projectFont).foregroundStyle(LumiPalette.textPrimary)
            if let color = project.node.appearance.color { ProjectColorDot(color: color) }
        }
        .treeRow(.project, verticalPadding: metrics.projectPadding, tint: groupTint(project))
        if !collapsed {
            // Agents are emitted as their own List rows (not nested inside a single
            // checkout cell) so each is individually selectable and supports swipe /
            // long-press delete.
            ForEach(project.checkouts) { checkout in
                checkoutHeader(checkout, in: project)
                ForEach(checkout.agents) { agent in
                    agentRow(agent, tint: groupTint(project))
                }
            }
        }
    }

    private func sectionHeader<Label: View>(id: String, collapsed: Bool,
                                            @ViewBuilder label: () -> Label) -> some View {
        Button {
            withAnimation(ProjectsMotion.fold) {
                if !collapsedProjects.insert(id).inserted { collapsedProjects.remove(id) }
            }
        } label: {
            HStack(spacing: 8) {
                label()
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption).foregroundStyle(LumiPalette.textSecondary)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Projects ▸ Other (Mac decision 108): terminals opened outside any project,
    /// grouped by folder. `+` opens a new Claude in one of the Mac's locations
    /// (home, roots) or next to existing loose terminals.
    @ViewBuilder
    private func otherSection(_ groups: [OtherGroupRowData], locations: [LooseLocation]) -> some View {
        let collapsed = collapsedProjects.contains(Self.otherSectionID)
        HStack(spacing: 8) {
            sectionHeader(id: Self.otherSectionID, collapsed: collapsed) {
                Image(systemName: "tray").font(metrics.projectFont).foregroundStyle(LumiPalette.textSecondary)
                Text("Other").font(metrics.projectFont).foregroundStyle(LumiPalette.textPrimary)
            }
            looseStartMenu(locations)
        }
        .treeRow(.project, verticalPadding: metrics.projectPadding)
        if !collapsed {
            ForEach(groups) { group in
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.caption).foregroundStyle(LumiPalette.textSecondary)
                    Text(group.node.label).font(metrics.checkoutFont)
                        .foregroundStyle(LumiPalette.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    startButton(id: group.id, label: "New Claude in \(group.node.label)") {
                        actions.start(group.node.path)
                    }
                }
                .treeRow(.checkout, verticalPadding: metrics.verticalPadding)
                ForEach(group.agents) { agent in
                    agentRow(agent)
                }
            }
        }
    }

    /// `+` of the Other header: pick the folder for a new loose Claude.
    @ViewBuilder
    private func looseStartMenu(_ locations: [LooseLocation]) -> some View {
        if let busy = actions.startingPath, locations.contains(where: { $0.path == busy }) {
            ProgressView().controlSize(.small).frame(width: 28, height: 24)
        } else {
            Menu {
                Section("New Claude in…") {
                    ForEach(locations) { location in
                        Button { actions.start(location.path) } label: {
                            Label(location.label, systemImage: location.label == "~" ? "house" : "folder")
                        }
                    }
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.body)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!actions.isOnline || actions.startingPath != nil || locations.isEmpty)
            .accessibilityLabel("New Claude outside a project")
        }
    }

    /// Collapse key for the Other section; NUL keeps it apart from project paths.
    private static let otherSectionID = "\u{0}other"

    @ViewBuilder
    private func checkoutHeader(_ checkout: CheckoutRowData, in project: ProjectRowData) -> some View {
        HStack(spacing: 8) {
            // "workspace" kind → branch icon; "original" (main checkout) → house icon
            Image(systemName: checkout.node.kind == "workspace" ? "arrow.triangle.branch" : "house")
                .font(.caption).foregroundStyle(LumiPalette.textSecondary)
            Text(checkoutDisplayTitle(checkout.node, in: project.node)).font(metrics.checkoutFont)
                .foregroundStyle(LumiPalette.textPrimary)
            if let branch = checkout.node.branch, !branch.isEmpty {
                Text(branch)
                    .font(metrics.detailFont).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            newAgentButton(checkout, in: project)
        }
        .treeRow(.checkout, verticalPadding: metrics.verticalPadding, tint: groupTint(project))
    }

    /// Tap: start a Claude agent right in this checkout's folder and open it.
    /// Long-press: menu that also offers creating a new branch from this one.
    @ViewBuilder
    private func newAgentButton(_ checkout: CheckoutRowData, in project: ProjectRowData) -> some View {
        let branch = checkout.node.branch.flatMap { $0.isEmpty ? nil : $0 }
        if actions.startingPath == checkout.id {
            ProgressView().controlSize(.small).frame(width: 28, height: 24)
        } else {
            Menu {
                Button { actions.start(checkout.node.path) } label: {
                    Label("New Claude on \(branch ?? checkout.node.title)", systemImage: "sparkle")
                }
                Button {
                    actions.newBranch(project.node.path, branch ?? "")
                } label: {
                    Label("New branch from \(branch ?? "current")…", systemImage: "arrow.triangle.branch")
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.body)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            } primaryAction: {
                actions.start(checkout.node.path)
            }
            .buttonStyle(.borderless)
            .disabled(!actions.isOnline || actions.startingPath != nil)
            .accessibilityLabel("New agent on \(branch ?? checkout.node.title)")
        }
    }

    /// `+` that starts a Claude right away (spinner while in flight).
    @ViewBuilder
    private func startButton(id: String, label: String, action: @escaping () -> Void) -> some View {
        if actions.startingPath == id {
            ProgressView().controlSize(.small).frame(width: 28, height: 24)
        } else {
            Button(action: action) {
                Image(systemName: "plus.circle")
                    .font(.body)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!actions.isOnline || actions.startingPath != nil)
            .accessibilityLabel(label)
        }
    }

    /// The project's color for its whole group, when the test toggle is on.
    private func groupTint(_ project: ProjectRowData) -> Color? {
        guard tintsGroups, let color = project.node.appearance.color else { return nil }
        return LumiPalette.projectColor(color)
    }

    @ViewBuilder
    private func agentRow(_ agent: AgentRowData, tint: Color? = nil) -> some View {
        Button {
            actions.open(agent.id)
        } label: {
            HStack(spacing: 8) {
                AgentActivityGlyph(activity: agent.activity)
                UsageProviderIcon(id: agent.provider, size: metrics.iconSize)
                Text(agent.title)
                    .font(metrics.agentFont)
                    .foregroundStyle(agent.needsAttention ? Color.orange : LumiPalette.textPrimary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer()
                if agent.activity == .running || agent.activity == .awaitingDecision {
                    Text(agent.activity.title)
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                }
                Text(PhoneRelativeTime.shortLabel(
                    agent.lastActivityAt,
                    now: Date().timeIntervalSince1970 * 1000
                ))
                .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .overlay(alignment: .leading) {
                if agent.needsAttention {
                    RoundedRectangle(cornerRadius: 2).fill(Color.orange).frame(width: 3)
                        .offset(x: -8)
                }
            }
        }
        .buttonStyle(.plain)
        .treeRow(.agent, verticalPadding: metrics.verticalPadding, tint: tint)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { actions.delete(agent.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) { actions.delete(agent.id) } label: {
                Label("Delete this chat", systemImage: "trash")
            }
        }
    }


    // MARK: - Chrome

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.plus").font(.title).foregroundStyle(.secondary)
            Text("No projects yet").foregroundStyle(.secondary)
            Text("Add a project on the Mac, or use +").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
        .lumiRow()
    }

    private var offlineBanner: some View {
        Label("Mac offline", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
            .font(.callout).foregroundStyle(.orange)
            .lumiRow()
    }

}
