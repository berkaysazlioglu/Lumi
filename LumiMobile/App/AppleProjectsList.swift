import SwiftUI
import LumiMobileKit

/// The Projects list: a compact inset-grouped list — one card per project whose
/// first row is the project itself on a band of its color (tap collapses the
/// card; press and hold drags it to a new place or opens Edit Project…, decision
/// 132), checkouts as rows with a `+`, agents as single-line rows under them,
/// `Other` for loose terminals, search, swipe / context-menu delete and system
/// colors throughout.
struct AppleProjectsList: View {
    let model: AppModel
    let actions: ProjectsListActions

    /// Collapsed sections survive relaunches, like Files' and Mail's sidebars.
    @AppStorage(Self.collapsedKey) private var collapsedStorage = ""
    /// Live fold state. `@AppStorage` writes land outside the animation
    /// transaction (the fold snapped open/closed), so the view animates this
    /// and only mirrors it to storage; seeded from storage on first appear.
    @State private var collapsedIDs: Set<String>?
    @State private var query = ""
    // Decision 132 reorder: the lifted project and where each header sits.
    @State private var drag: ProjectDragState?
    @State private var headerFrames: [String: CGRect] = [:]
    /// The list's global origin — turns the global finger into the preview's position.
    @State private var listOrigin: CGPoint = .zero
    /// The header's tap lands as the finger lifts after a drag (or a hold);
    /// fold toggles are ignored while a project is lifted and until then.
    @State private var foldLockedUntil = Date.distantPast
    // Test controls (shared with the Lumi layout): Group Color + A− / A+.
    @AppStorage(ProjectsLookControls.tintKey) private var tintsGroups = false
    @AppStorage(ProjectsRowMetrics.scaleKey) private var rowScale = 1.0

    /// Collapse key for the Other section; NUL keeps it apart from project paths.
    private static let otherSectionID = "\u{0}other"
    private static let collapsedKey = "appleProjectsCollapsed"
    /// Paths never hold a newline, so it separates the stored section ids.
    private static let collapsedSeparator: Character = "\n"
    /// The header block lines up with the cards' edges.
    private static let headerInsets = EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0)

    var body: some View {
        let filter = AppleProjectsFilter(query: query)
        let projects = filter.projects(model.projectTree)
        let others = filter.others(model.otherGroups)
        let locations = looseStartLocations(model.projectsSnapshot)
        List {
            topSection(isSearching: filter.isActive)
            if !filter.isActive && model.projectTree.isEmpty { noProjects }
            ForEach(projects) { projectSection($0, isSearching: filter.isActive) }
            if !others.isEmpty || (!filter.isActive && !locations.isEmpty) {
                otherSection(others, locations: locations, isSearching: filter.isActive)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .environment(\.defaultMinListRowHeight, AppleProjectsMetrics.minRowHeight * rowScale)
        .navigationTitle("Projects")
        .searchable(text: $query, prompt: "Projects, Branches, Chats")
        // A drop (or the Mac's reorder) slides the cards into place.
        .animation(ProjectsMotion.fold, value: projects.map(\.id))
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { listOrigin = $0 }
        .onPreferenceChange(ProjectHeaderFramesKey.self) { headerFrames = $0 }
        .overlay(alignment: .topLeading) { dragPreview(projects) }
        // A lifted project pins the list: otherwise it scrolls (or rubber-bands)
        // with the finger and the finger never reaches the other cards.
        .scrollDisabled(drag != nil)
        .sensoryFeedback(.impact, trigger: drag?.path)
        .sensoryFeedback(.selection, trigger: drag?.target)
        .overlay {
            if filter.isActive && projects.isEmpty && others.isEmpty { ContentUnavailableView.search(text: query) }
        }
    }

    // MARK: - Sections

    /// Usage indicators over the look controls as one header block (not while
    /// searching — only results then) and, when the Mac is away, its status.
    @ViewBuilder private func topSection(isSearching: Bool) -> some View {
        if !isSearching {
            ProjectsListHeader(usage: model.usage, isStale: !model.macOnline)
                .listRowInsets(Self.headerInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        if !model.macOnline {
            Section { offlineRow }
        }
    }

    /// The project row heads its own card, so the project reads as one group
    /// with its checkouts and agents.
    private func projectSection(_ slice: AppleProjectSlice, isSearching: Bool) -> some View {
        let isExpanded = expansion(slice.id, isSearching: isSearching)
        let node = slice.project.node
        return Section {
            AppleGroupHeaderRow(tint: AppleProjectBadge.color(node.appearance.color),
                                isExpanded: isExpanded,
                                collapsedCount: slice.agentCount,
                                isDropTarget: drag?.target == node.path,
                                onEdit: { actions.edit(node) },
                                isEditEnabled: actions.isOnline) {
                AppleProjectBadge(appearance: node.appearance)
                Text(node.name)
            }
            .projectDragSource(node, isEnabled: !isSearching, onChanged: dragChanged, onEnded: dragEnded)
            .opacity(drag?.path == node.path ? Self.liftedOpacity : 1)
            .projectEditable(node, actions: actions)
            if isExpanded.wrappedValue {
                let tint = groupTint(slice.project.node)
                ForEach(slice.checkouts) { checkout in
                    AppleCheckoutRow(checkout: checkout.checkout, project: slice.project.node,
                                     actions: actions, tint: tint)
                    ForEach(checkout.agents) { AppleAgentRow(agent: $0, actions: actions, tint: tint) }
                }
            }
        }
    }

    /// Projects ▸ Other (Mac decision 108): terminals outside any project, by folder.
    private func otherSection(_ groups: [AppleOtherSlice], locations: [LooseLocation],
                              isSearching: Bool) -> some View {
        let isExpanded = expansion(Self.otherSectionID, isSearching: isSearching)
        return Section {
            AppleGroupHeaderRow(tint: Color(.systemGray), isExpanded: isExpanded,
                                collapsedCount: groups.reduce(0) { $0 + $1.agents.count }) {
                AppleSymbolBadge(symbol: "tray.full", color: Color(.systemGray))
                Text("Other")
            }
            if isExpanded.wrappedValue {
                ForEach(groups) { group in
                    AppleFolderRow(group: group.group.node, actions: actions)
                    ForEach(group.agents) { AppleAgentRow(agent: $0, actions: actions) }
                }
                if !locations.isEmpty { AppleLooseStartRow(locations: locations, actions: actions) }
            }
        }
    }

    // MARK: - Reorder (decision 132)

    private static let liftedOpacity = 0.4

    private func dragChanged(_ path: String, _ location: CGPoint) {
        drag = ProjectDragState(path: path, location: location,
                                target: ProjectReorder.target(at: location.y, headers: headerFrames, dragging: path))
    }

    private func dragEnded() {
        guard let drag else { return }
        self.drag = nil
        foldLockedUntil = Date().addingTimeInterval(ProjectReorder.foldLockAfterDrop)
        if let target = drag.target { actions.move(drag.path, target) }
    }

    @ViewBuilder private func dragPreview(_ projects: [AppleProjectSlice]) -> some View {
        if let drag, let project = projects.first(where: { $0.id == drag.path })?.project.node {
            ProjectDragPreview(project: project)
                .position(x: drag.location.x - listOrigin.x, y: drag.location.y - listOrigin.y)
        }
    }

    // MARK: - Chrome

    private var offlineRow: some View {
        Label {
            VStack(alignment: .leading, spacing: AppleProjectsMetrics.subtitleSpacing) {
                Text("Mac Offline").font(.subheadline.weight(.semibold))
                Text("Agents can't be started until your Mac reconnects.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                .foregroundStyle(.orange)
        }
    }

    /// Empty state as a list row, so `Other` (loose terminals) still shows below it.
    private var noProjects: some View {
        ContentUnavailableView {
            Label("No Projects", systemImage: "folder.badge.plus")
        } description: {
            Text("Add a project on your Mac, or tap + to add one.")
        }
        .listRowBackground(Color.clear)
    }

    /// The project's color over its whole card, when the Group Color test toggle is on.
    private func groupTint(_ project: ProjectNode) -> Color? {
        guard tintsGroups, project.appearance.color != nil else { return nil }
        return AppleProjectBadge.color(project.appearance.color)
    }

    private var collapsed: Set<String> {
        collapsedIDs ?? Set(collapsedStorage.split(separator: Self.collapsedSeparator).map(String.init))
    }

    /// Search results always show expanded; collapsing then is not remembered.
    private func expansion(_ id: String, isSearching: Bool) -> Binding<Bool> {
        Binding(
            get: { isSearching || !collapsed.contains(id) },
            set: { isExpanded in
                guard !isSearching, drag == nil, Date() >= foldLockedUntil else { return }
                var ids = collapsed
                if isExpanded { ids.remove(id) } else { ids.insert(id) }
                withAnimation(ProjectsMotion.fold) { collapsedIDs = ids }
                collapsedStorage = ids.sorted().joined(separator: String(Self.collapsedSeparator))
            }
        )
    }
}

// MARK: - Other rows

/// A loose-terminal folder: its path and a `+` that starts a Claude there.
private struct AppleFolderRow: View {
    let group: OtherGroupNode
    let actions: ProjectsListActions
    @AppStorage(ProjectsRowMetrics.scaleKey) private var scale = 1.0

    var body: some View {
        HStack(spacing: AppleProjectsMetrics.rowSpacing) {
            Image(systemName: group.label == "~" ? "house" : "folder")
                .font(AppleProjectsMetrics.titleFont(scale))
                .foregroundStyle(.secondary)
                .frame(width: AppleProjectsMetrics.iconColumn * scale)
            Text(group.label).font(AppleProjectsMetrics.titleFont(scale))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            AppleStartMenu(path: group.path, actions: actions,
                           accessibilityLabel: "New agent in \(group.label)")
        }
        .appleProjectsRow(scale: scale)
    }
}

/// Reminders' "Add List"-style row: a tinted menu that picks the folder for a
/// new loose Claude (the Mac's home and roots, then existing loose folders).
private struct AppleLooseStartRow: View {
    let locations: [LooseLocation]
    let actions: ProjectsListActions
    @AppStorage(ProjectsRowMetrics.scaleKey) private var scale = 1.0

    private var isBusy: Bool {
        guard let busy = actions.startingPath else { return false }
        return locations.contains { $0.path == busy }
    }

    var body: some View {
        Menu {
            Section("New Claude in…") {
                ForEach(locations) { location in
                    Button { actions.start(location.path, nil) } label: {
                        Label(location.label, systemImage: location.label == "~" ? "house" : "folder")
                    }
                }
            }
        } label: {
            HStack(spacing: AppleProjectsMetrics.rowSpacing) {
                Group {
                    if isBusy { ProgressView() } else { Image(systemName: "plus.circle.fill") }
                }
                .frame(width: AppleProjectsMetrics.iconColumn)
                Text("New Claude in…").font(AppleProjectsMetrics.titleFont(scale))
            }
        }
        .disabled(!actions.isOnline || actions.startingPath != nil)
        .appleProjectsRow(scale: scale)
    }
}
