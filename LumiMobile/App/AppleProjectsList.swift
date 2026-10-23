import SwiftUI
import LumiMobileKit

/// Apple-standard Projects list (Settings ▸ Apple Layout): a system sidebar-style
/// list like Files ▸ Browse or Mail's mailboxes — one collapsible section per
/// project (Reminders-style colored badge), checkouts as rows with a `+`,
/// agents as Mail-like two-line rows under them, `Other` for loose terminals,
/// search, swipe / context-menu delete and system colors throughout.
struct AppleProjectsList: View {
    let model: AppModel
    let actions: ProjectsListActions

    /// Collapsed sections survive relaunches, like Files' and Mail's sidebars.
    @AppStorage(Self.collapsedKey) private var collapsedStorage = ""
    @State private var query = ""

    /// Collapse key for the Other section; NUL keeps it apart from project paths.
    private static let otherSectionID = "\u{0}other"
    private static let collapsedKey = "appleProjectsCollapsed"
    /// Paths never hold a newline, so it separates the stored section ids.
    private static let collapsedSeparator: Character = "\n"
    /// The usage strip lines up with the section headers (row content is clipped at 0).
    private static let stripInset: CGFloat = 16

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
        .listStyle(.sidebar)
        .navigationTitle("Projects")
        .searchable(text: $query, prompt: "Projects, Branches, Chats")
        .overlay {
            if filter.isActive && projects.isEmpty && others.isEmpty { ContentUnavailableView.search(text: query) }
        }
    }

    // MARK: - Sections

    /// Usage indicators (not while searching — only results then) and, when
    /// the Mac is away, its status.
    @ViewBuilder private func topSection(isSearching: Bool) -> some View {
        if !isSearching, model.usage?.isEmpty == false {
            ProjectsUsageStrip(report: model.usage, isStale: !model.macOnline)
                .listRowInsets(EdgeInsets(top: 0, leading: Self.stripInset, bottom: 0, trailing: Self.stripInset))
                .listRowBackground(Color.clear)
        }
        if !model.macOnline {
            Section { offlineRow }
        }
    }

    private func projectSection(_ slice: AppleProjectSlice, isSearching: Bool) -> some View {
        Section(isExpanded: expansion(slice.id, isSearching: isSearching)) {
            ForEach(slice.checkouts) { checkout in
                AppleCheckoutRow(checkout: checkout.checkout, project: slice.project.node, actions: actions)
                ForEach(checkout.agents) { AppleAgentRow(agent: $0, actions: actions) }
            }
        } header: {
            AppleProjectHeader(node: slice.project.node,
                               collapsedCount: !isSearching && collapsed.contains(slice.id) ? slice.agentCount : nil)
        }
        .headerProminence(.increased)
    }

    /// Projects ▸ Other (Mac decision 108): terminals outside any project, by folder.
    private func otherSection(_ groups: [AppleOtherSlice], locations: [LooseLocation],
                              isSearching: Bool) -> some View {
        Section(isExpanded: expansion(Self.otherSectionID, isSearching: isSearching)) {
            ForEach(groups) { group in
                AppleFolderRow(group: group.group.node, actions: actions)
                ForEach(group.agents) { AppleAgentRow(agent: $0, actions: actions) }
            }
            if !locations.isEmpty { AppleLooseStartRow(locations: locations, actions: actions)}
        } header: {
            HStack(spacing: AppleProjectsMetrics.rowSpacing) {
                AppleSymbolBadge(symbol: "tray.full", color: Color(.systemGray))
                Text("Other")
            }
        }
        .headerProminence(.increased)
    }

    // MARK: - Chrome

    private var offlineRow: some View {
        Label {
            VStack(alignment: .leading, spacing: AppleProjectsMetrics.subtitleSpacing) {
                Text("Mac Offline").font(.headline)
                Text("Agents can't be started until your Mac reconnects.")
                    .font(.subheadline).foregroundStyle(.secondary)
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

    private var collapsed: Set<String> {
        Set(collapsedStorage.split(separator: Self.collapsedSeparator).map(String.init))
    }

    /// Search results always show expanded; collapsing then is not remembered.
    private func expansion(_ id: String, isSearching: Bool) -> Binding<Bool> {
        Binding(
            get: { isSearching || !collapsed.contains(id) },
            set: { isExpanded in
                guard !isSearching else { return }
                var ids = collapsed
                if isExpanded { ids.remove(id) } else { ids.insert(id) }
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

    var body: some View {
        HStack(spacing: AppleProjectsMetrics.rowSpacing) {
            Image(systemName: group.label == "~" ? "house" : "folder")
                .foregroundStyle(.secondary)
                .frame(width: AppleProjectsMetrics.iconColumn)
            Text(group.label).font(.body.weight(.medium))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            AppleStartMenu(path: group.path, actions: actions,
                           accessibilityLabel: "New Claude in \(group.label)") {
                Button { actions.start(group.path) } label: {
                    Label("New Claude in \(group.label)", systemImage: "plus.bubble")
                }
            }
        }
    }
}

/// Reminders' "Add List"-style row: a tinted menu that picks the folder for a
/// new loose Claude (the Mac's home and roots, then existing loose folders).
private struct AppleLooseStartRow: View {
    let locations: [LooseLocation]
    let actions: ProjectsListActions

    private var isBusy: Bool {
        guard let busy = actions.startingPath else { return false }
        return locations.contains { $0.path == busy }
    }

    var body: some View {
        Menu {
            Section("New Claude in…") {
                ForEach(locations) { location in
                    Button { actions.start(location.path) } label: {
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
                Text("New Claude in…")
            }
        }
        .disabled(!actions.isOnline || actions.startingPath != nil)
    }
}
