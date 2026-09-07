import LumiKit
import LumiState
import SwiftUI

/// Projects and their locally created workspaces. The project list is derived
/// from RepoStore; workspace records are the only additional state shown here.
public struct ProjectsPanel: View {
    @Shell private var shell
    @State private var isCollapsed = false
    @State private var searchText = ""
    @State private var collapsedProjects = Set<String>()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                title: "Projects", icon: "folder", count: .neutral(originalProjects.count),
                disclosure: .leading, isExpanded: !isCollapsed,
                onToggle: { isCollapsed.toggle() }
            ) {
                addProjectButton
            }
                .padding(.bottom, Theme.Spacing.xs)
            if !isCollapsed {
                LumiTextInput(text: $searchText, placeholder: "Search projects")
                    .padding(.bottom, Theme.Spacing.sm)
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
                            if !collapsedProjects.contains(project.path) || !searchText.isEmpty || operationBelongs(to: project) {
                                originalRow(project)
                                ForEach(shell.workspaces.workspaces(for: project.path)) { workspace in
                                    if !operationBelongs(to: project) || shell.workspaces.lastCreated?.path != workspace.path {
                                        workspaceRow(workspace)
                                    }
                                }
                                if operationBelongs(to: project) { operationRow }
                            }
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: shell.workspaces.hasBackgroundOperation) { _, active in
            if active { isCollapsed = false; searchText = "" }
        }
    }

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

    private var originalProjects: [Repo] {
        shell.workspaces.addedProjects
    }

    private var filteredProjects: [Repo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return originalProjects }
        return originalProjects.filter { project in
            project.name.lowercased().contains(query) || shell.workspaces.workspaces(for: project.path).contains {
                $0.name.lowercased().contains(query) || $0.branch.lowercased().contains(query)
            }
        }
    }

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
            Button("Remove from Projects") { Task { await shell.workspaces.removeProject(project) } }
                .disabled(shell.workspaces.isCreating && operationBelongs(to: project))
        }
    }

    private func operationBelongs(to project: Repo) -> Bool {
        shell.workspaces.hasBackgroundOperation && shell.workspaces.selectedProjectPath == project.path
    }

    private var operationRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                if shell.workspaces.isCreating {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: shell.workspaces.lastCreated == nil ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundStyle(shell.workspaces.lastCreated == nil ? Theme.warning : Theme.success)
                }
                Text(shell.workspaces.name)
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            if shell.workspaces.isCreating {
                Text(shell.workspaces.phaseText)
                    .font(Theme.Typography.captionMono).foregroundStyle(Theme.textSecondary)
            } else {
                if let message = shell.workspaces.errorMessage ?? shell.workspaces.warningMessage {
                    Text(message).font(Theme.Typography.captionMono).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack { operationActions }
                    VStack(alignment: .leading) { operationActions }
                }
            }
        }
        .padding(.leading, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.sm)
    }

    @ViewBuilder
    private var operationActions: some View {
        if shell.workspaces.needsSave {
            Button("Retry Save") { Task { await shell.workspaces.retrySave() } }
        }
        if shell.workspaces.libraryNeedsRetry {
            Button("Retry Library") { Task { await shell.workspaces.retryLibrary() } }
        }
        if let created = shell.workspaces.lastCreated, !shell.workspaces.needsSave {
            Button(shell.workspaces.libraryNeedsRetry ? "Open without Library" : "Open") {
                shell.openCreatedWorkspace(created, agent: shell.workspaces.agent)
                shell.workspaces.clearForm()
            }
        } else if shell.workspaces.lastCreated == nil {
            Button("Retry") { shell.workspaces.startCreation(projects: shell.repos.repos) }
        }
        Button("Dismiss") { shell.workspaces.clearForm() }
    }

    private func originalRow(_ project: Repo) -> some View {
        Button { shell.navigation.openTab(project.path) } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "doc.plaintext").foregroundStyle(Theme.textMuted)
                Text("Original").font(Theme.Typography.captionMono).foregroundStyle(Theme.textMuted)
                Spacer(minLength: 0)
                sessionSummary(for: project.path)
            }
            .padding(.leading, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(shell.navigation.activeRepoPath == project.path ? Theme.bgElevated : .clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .accessibilityLabel("Open original project \(project.name)")
    }

    private func workspaceRow(_ workspace: ProjectWorkspace) -> some View {
        Button {
            shell.navigation.openTab(workspace.path)
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(Theme.textMuted)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(workspace.name)
                        .font(Theme.Typography.labelMono)
                        .foregroundStyle(Theme.textSecondary)
                    Text(workspace.branch)
                        .font(Theme.Typography.captionMono)
                        .foregroundStyle(Theme.textMuted)
                }
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: 0)
                Text(workspace.scm.title)
                    .font(Theme.Typography.captionMono)
                    .foregroundStyle(Theme.textMuted)
                sessionSummary(for: workspace.path)
                if shell.workspaces.isMissing(workspace) {
                    Text("Missing")
                        .font(Theme.Typography.captionMono)
                        .foregroundStyle(Theme.warning)
                }
            }
            .padding(.leading, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(shell.navigation.activeRepoPath == workspace.path ? Theme.bgElevated : .clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .disabled(shell.workspaces.isMissing(workspace))
        .help(workspace.path)
        .accessibilityLabel("Open workspace \(workspace.name)")
    }

    @ViewBuilder
    private func sessionSummary(for path: String) -> some View {
        let sessions = shell.terminals.terminals(in: path)
        if !sessions.isEmpty {
            HStack(spacing: Theme.Spacing.xs) {
                Circle().fill(Theme.statusColor(for:
                    [TerminalStatus.error, .waitingUnseen, .working, .waitingFocused, .waitingSeen, .idle]
                        .first { status in sessions.contains { $0.status == status } } ?? .idle))
                    .frame(width: Theme.Spacing.sm, height: Theme.Spacing.sm)
                Text("\(sessions.count)").font(Theme.Typography.captionMono).foregroundStyle(Theme.textMuted)
            }
        }
    }
}

#if DEBUG
private extension ShellContext {
    static var projectsPanelPreview: ShellContext { .preview() }
}

#Preview("ProjectsPanel") {
    ProjectsPanel()
        .frame(width: 280, height: 420)
        .background(Theme.bgSurface)
        .environment(\.shell, ShellContext.projectsPanelPreview)
}
#endif
