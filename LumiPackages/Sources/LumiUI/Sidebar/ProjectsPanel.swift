import LumiKit
import LumiState
import SwiftUI

/// Projects paneli (karar 46–49): proje → checkout (original / workspace) →
/// ajan satırları. Orca sidebar'ının sadeliği hedeftir: çalışan ve biten
/// ajanlar tek bakışta ayrışır, satırlar sağ tıkla yönetilir.
///
/// Panel yalnız state gösterir: proje listesi `ProjectWorkspaceStore`'dan,
/// canlı ajanlar `TerminalListStore`'dan okunur; her eylem bir store
/// intent'i ya da `ShellContext` koordinasyonudur.
public struct ProjectsPanel: View {
    @Shell private var shell
    @State private var isCollapsed = false
    @State private var searchText = ""
    @State private var collapsedProjects = Set<String>()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                title: "Projects", icon: "folder", count: .neutral(filteredProjects.count),
                disclosure: .leading, isExpanded: !isCollapsed,
                onToggle: { isCollapsed.toggle() }
            ) {
                addProjectButton
            }
            .padding(.bottom, Theme.Spacing.xs)
            if !isCollapsed {
                LumiTextInput(text: $searchText, placeholder: "Search projects")
                    .padding(.bottom, Theme.Spacing.sm)
                projectList
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: shell.workspaces.hasBackgroundOperation) { _, active in
            if active { isCollapsed = false; searchText = "" }
        }
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                if filteredProjects.isEmpty {
                    Text(searchText.isEmpty ? "No projects" : "No matching projects")
                        .font(Theme.Typography.captionMono)
                        .foregroundStyle(Theme.textMuted)
                        .padding(.vertical, Theme.Spacing.lg)
                }
                ForEach(filteredProjects) { project in
                    projectRow(project)
                    if isExpanded(project) {
                        CheckoutRow(checkout: .original(project))
                        ForEach(shell.workspaces.workspaces(for: project.path)) { workspace in
                            if shell.workspaces.lastCreated?.path != workspace.path || !operationBelongs(to: project) {
                                CheckoutRow(checkout: .workspace(workspace))
                            }
                        }
                        if operationBelongs(to: project) { WorkspaceOperationRow() }
                    }
                }
            }
        }
    }

    // MARK: - Üst şerit

    private var addProjectButton: some View {
        IconButton(systemName: "plus", label: "Add project") {
            shell.dialogs.setPresented(.sidebarProjectSelector, !shell.dialogs.isPresenting(.sidebarProjectSelector))
        }
        .popover(isPresented: Binding(
            get: { shell.dialogs.isPresenting(.sidebarProjectSelector) },
            set: { shell.dialogs.setPresented(.sidebarProjectSelector, $0) }
        )) {
            RepoSelectorView(
                groups: shell.repos.groupedRepos,
                excludedRepoPaths: Set(shell.workspaces.sidebarProjectPaths + shell.workspaces.records.map(\.path)),
                collapsedGroups: Binding(
                    get: { shell.dialogs.collapsedRepoGroups },
                    set: { shell.dialogs.collapsedRepoGroups = $0 }
                )
            ) { repo in
                Task { await shell.addSidebarProject(repo) }
            }
        }
    }

    // MARK: - Türevler

    private var filteredProjects: [Repo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let projects = shell.workspaces.addedProjects
        guard !query.isEmpty else { return projects }
        return projects.filter { project in
            project.name.lowercased().contains(query) || shell.workspaces.workspaces(for: project.path).contains {
                $0.name.lowercased().contains(query) || $0.branch.lowercased().contains(query)
            }
        }
    }

    private func isExpanded(_ project: Repo) -> Bool {
        !collapsedProjects.contains(project.path) || !searchText.isEmpty || operationBelongs(to: project)
    }

    private func operationBelongs(to project: Repo) -> Bool {
        shell.workspaces.hasBackgroundOperation && shell.workspaces.selectedProjectPath == project.path
    }

    // MARK: - Proje satırı

    private func projectRow(_ project: Repo) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                if !collapsedProjects.insert(project.path).inserted { collapsedProjects.remove(project.path) }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: collapsedProjects.contains(project.path) ? "chevron.right" : "chevron.down")
                        .font(Theme.Typography.captionMono)
                        .foregroundStyle(Theme.textMuted)
                    Image(systemName: "folder")
                        .foregroundStyle(Theme.accentPrimary)
                        .accessibilityHidden(true)
                    Text(project.name)
                        .font(Theme.Typography.bodyMono)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle workspaces for \(project.name)")
            Spacer(minLength: 0)
            IconButton(systemName: "plus", label: "Create workspace for \(project.name)", size: .label, side: Theme.Spacing.xxl) {
                shell.dialogs.present(.createWorkspace(projectPath: project.path))
            }
            .disabled(shell.workspaces.isCreating)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .contextMenu {
            Button("Create Workspace…") { shell.dialogs.present(.createWorkspace(projectPath: project.path)) }
                .disabled(shell.workspaces.isCreating)
            Button("Reveal in Finder") { shell.actions.revealPath(project.path) }
            Button("Copy Path") { Pasteboard.copy(project.path) }
            Divider()
            Button("Remove from Projects") { Task { await shell.workspaces.removeProject(project) } }
                .disabled(shell.workspaces.isCreating && operationBelongs(to: project))
        }
    }
}

/// Pano kopyası — tek yer (ExplorerRowView ile aynı çağrı).
enum Pasteboard {
    @MainActor
    static func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

#if DEBUG
#Preview("ProjectsPanel") {
    ProjectsPanel()
        .frame(width: 280, height: 420)
        .background(Theme.bgSurface)
        .environment(\.shell, ShellContext.preview())
}
#endif
