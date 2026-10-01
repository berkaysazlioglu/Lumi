import LumiKit
import LumiState
import SwiftUI

/// Projects paneli (karar 48–51): proje → checkout (original / workspace) →
/// ajan satırları. Orca sidebar'ının sadeliği hedeftir: çalışan ve biten
/// ajanlar tek bakışta ayrışır, satırlar sağ tıkla yönetilir.
///
/// Panel yalnız state gösterir: proje listesi `ProjectWorkspaceStore`'dan,
/// canlı ajanlar `TerminalListStore`'dan okunur; her eylem bir store
/// intent'i ya da `ShellContext` koordinasyonudur.
public struct ProjectsPanel: View {
    @Shell private var shell
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var collapsedProjects = Set<String>()
    @FocusState private var focusedProjectAction: String?
    /// Sağ tık menüsü açık olan projenin yolu (karar 53 deseni).
    @State private var menuProjectPath: String?

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                title: "Projects", icon: "folder", count: .neutral(filteredProjects.count),
                disclosure: .none, onToggle: nil
            ) {
                searchButton
                addProjectButton
            }
            .padding(.bottom, isSearchVisible ? Theme.Spacing.sm : Theme.Spacing.xs)
            if isSearchVisible {
                LumiTextInput(text: $searchText, placeholder: "Search projects and workspaces")
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .padding(.bottom, Theme.Spacing.sm)
            }
            projectList
        }
        .padding(Theme.Spacing.lg)
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: shell.workspaces.hasBackgroundOperation) { _, active in
            if active { searchText = "" }
        }
        .animation(Theme.Motion.quickEase, value: isSearchVisible)
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                if filteredProjects.isEmpty {
                    emptyState
                }
                ForEach(filteredProjects) { project in
                    VStack(alignment: .leading, spacing: 0) {
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
                    .padding(.bottom, Theme.Spacing.xs)
                }
            }
        }
    }

    // MARK: - Üst şerit

    private var searchButton: some View {
        IconButton(
            systemName: isSearchVisible ? "xmark" : "magnifyingglass",
            label: isSearchVisible ? "Close project search" : "Search projects"
        ) {
            isSearchVisible.toggle()
            if !isSearchVisible { searchText = "" }
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

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: searchText.isEmpty ? "folder.badge.plus" : "magnifyingglass")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.textMuted)
            Text(searchText.isEmpty ? "No projects yet" : "No matching projects")
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textSecondary)
            if searchText.isEmpty {
                Text("Use + to add a project")
                    .font(Theme.Typography.captionMono)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
    }

    private func isExpanded(_ project: Repo) -> Bool {
        !collapsedProjects.contains(project.path) || !searchText.isEmpty || operationBelongs(to: project)
    }

    private func operationBelongs(to project: Repo) -> Bool {
        shell.workspaces.hasBackgroundOperation && shell.workspaces.selectedProjectPath == project.path
    }

    // MARK: - Proje satırı

    private func projectRow(_ project: Repo) -> some View {
        HoverReader { isHovering in
            projectRowContent(project, isHovering: isHovering)
        }
        // Native `contextMenu` koyu panelde sistem görünümüyle çıkıyordu;
        // menü Lumi'nin kendi `PopoverMenu`suyla çizilir (karar 53 deseni).
        .onRightClick { menuProjectPath = project.path }
        .popover(
            isPresented: Binding(
                get: { menuProjectPath == project.path },
                set: { if !$0 { menuProjectPath = nil } }
            ),
            arrowEdge: .bottom
        ) {
            PopoverMenu(items: menuItems(project), dismiss: { menuProjectPath = nil })
        }
    }

    private func menuItems(_ project: Repo) -> [PopoverMenu.Item] {
        [
            .action("Create Workspace…", icon: "plus", isEnabled: !shell.workspaces.isCreating) {
                shell.dialogs.present(.createWorkspace(projectPath: project.path))
            },
            .divider,
            .action("Open CLAUDE.md", icon: "doc.text", isEnabled: hasClaudeInstructions(project)) {
                Task { await shell.fileViewer.presentView(repoPath: project.path, filePath: Self.claudeInstructionsFile) }
            },
            .action("Reveal in Finder", icon: "folder") { shell.actions.revealPath(project.path) },
            .action("Copy Path", icon: "doc.on.doc") { Pasteboard.copy(project.path) },
            .divider,
            .action(
                "Remove from Projects", icon: "trash", isDestructive: true,
                isEnabled: !(shell.workspaces.isCreating && operationBelongs(to: project))
            ) {
                shell.requestRemoveProject(project)
            },
        ]
    }

    /// Proje kökündeki CLAUDE.md. Menü yalnız sağ tıkta kurulduğu için
    /// dosya kontrolü her çizimde değil, açılışta bir kez yapılır.
    static let claudeInstructionsFile = "CLAUDE.md"

    private func hasClaudeInstructions(_ project: Repo) -> Bool {
        FileManager.default.fileExists(
            atPath: URL(fileURLWithPath: project.path).appendingPathComponent(Self.claudeInstructionsFile).path
        )
    }

    private func projectRowContent(_ project: Repo, isHovering: Bool) -> some View {
        let actionFocusPrefix = project.path + "#"
        let showsActions = isHovering || focusedProjectAction?.hasPrefix(actionFocusPrefix) == true
        return HStack(spacing: Theme.Spacing.sm) {
            Button {
                toggleProject(project)
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "folder")
                        .foregroundStyle(Theme.accentPrimary)
                        .accessibilityHidden(true)
                    Text(project.name)
                        .font(Theme.Typography.mono(.body, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle workspaces for \(project.name)")
            HStack(spacing: Theme.Spacing.xxs) {
                IconButton(
                    systemName: "ellipsis", label: "Project actions for \(project.name)",
                    size: .label, side: Theme.Spacing.xxl
                ) {
                    menuProjectPath = project.path
                }
                .focused($focusedProjectAction, equals: actionFocusPrefix + "menu")
                IconButton(
                    systemName: "plus", label: "Create workspace for \(project.name)",
                    size: .label, side: Theme.Spacing.xxl
                ) {
                    shell.dialogs.present(.createWorkspace(projectPath: project.path))
                }
                .disabled(shell.workspaces.isCreating)
                .focused($focusedProjectAction, equals: actionFocusPrefix + "create")
            }
            .opacity(showsActions ? 1 : 0)
            .animation(Theme.Motion.quickEase, value: showsActions)
            Button { toggleProject(project) } label: {
                Image(systemName: collapsedProjects.contains(project.path) ? "chevron.right" : "chevron.down")
                    .font(Theme.Typography.captionMono)
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: Theme.Spacing.xl, height: Theme.Spacing.xl)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.xxs)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func toggleProject(_ project: Repo) {
        if !collapsedProjects.insert(project.path).inserted {
            collapsedProjects.remove(project.path)
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
