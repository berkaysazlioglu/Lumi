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
                IconButton(systemName: "plus", label: "Add project") {
                    Task { await shell.addProject() }
                }
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
                            if !collapsedProjects.contains(project.path) || !searchText.isEmpty {
                                originalRow(project)
                                ForEach(shell.workspaces.workspaces(for: project.path)) { workspace in
                                    workspaceRow(workspace)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var originalProjects: [Repo] {
        let managedPaths = Set(shell.workspaces.records.map(\.path))
        return shell.repos.repos.filter { !managedPaths.contains($0.path) }
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
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
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
