import LumiKit
import LumiState
import SwiftUI

public struct CreateWorkspaceOverlay: View {
    @Shell private var shell
    let projectPath: String?
    @State private var selectedProject: Repo?
    @State private var isAdvancedExpanded = false
    @State private var formHeight: CGFloat = 1

    public init(projectPath: String? = nil) { self.projectPath = projectPath }

    private var effectiveProjectPath: String? {
        if let projectPath { return projectPath }
        guard case .createWorkspace(let path) = shell.dialogs.active else { return nil }
        return path
    }

    private var project: Repo? {
        selectedProject ?? effectiveProjectPath.flatMap { shell.repos.repo(at: $0) }
    }

    public var body: some View {
        GeometryReader { geometry in
            ModalOverlay(onDismiss: dismiss) {
                Panel(variant: .modal) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        header
                        if let project {
                            projectPicker(project)
                            ScrollView {
                                form(project)
                                    .background(GeometryReader { content in
                                        Color.clear.preference(key: WorkspaceFormHeight.self, value: content.size.height)
                                    })
                            }
                            .onPreferenceChange(WorkspaceFormHeight.self) { height in
                                Task { @MainActor in formHeight = height }
                            }
                            .frame(height: min(formHeight, max(100, min(680, geometry.size.height - Theme.Spacing.xxxl * 2) - 180)))
                        } else {
                            Text("Project is no longer available.")
                                .font(Theme.Typography.bodyMono)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    .padding(Theme.Spacing.xxxl)
                    .frame(width: 520)
                }
            }
            .task(id: effectiveProjectPath) {
                guard let effectiveProjectPath else { return }
                guard let project = shell.repos.repo(at: effectiveProjectPath) else { return }
                selectedProject = project
                await shell.workspaces.selectProject(project)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Create workspace")
                    .font(Theme.Typography.titleMono)
                    .foregroundStyle(Theme.textPrimary)
                Text("Create a local workspace from this project")
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 0)
            IconButton(systemName: "xmark", label: "Cancel", size: .body, side: Theme.Spacing.xxl, action: dismiss)
        }
    }

    private func projectPicker(_ project: Repo) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Project")
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textSecondary)
            Picker("Project", selection: Binding(
                get: { selectedProject?.path ?? project.path },
                set: { path in
                    guard let next = projectCandidates.first(where: { $0.path == path }) else { return }
                    selectedProject = next
                    Task { await shell.workspaces.selectProject(next) }
                }
            )) {
                ForEach(projectCandidates) { candidate in
                    Text(candidate.name).tag(candidate.path)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .foregroundStyle(Theme.textPrimary)
            .disabled(shell.workspaces.isCreating || shell.workspaces.lastCreated != nil)
        }
    }

    private var projectCandidates: [Repo] {
        shell.workspaces.addedProjects
    }

    private func form(_ project: Repo) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            field("Name") {
                LumiTextInput(text: binding(\.name), placeholder: "Workspace name", autofocus: true)
                    .disabled(shell.workspaces.lastCreated != nil)
            }
            field("Agent") {
                Picker("Agent", selection: binding(\.agent)) {
                    ForEach(WorkspaceAgent.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            .labelsHidden()
                .foregroundStyle(Theme.textPrimary)
            }
            if shell.workspaces.isInspecting {
                Label("Inspecting project…", systemImage: "hourglass")
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textMuted)
            } else if let source = shell.workspaces.source {
                detected(source)
            }
            if shell.workspaces.source?.isUnityProject == true {
                unitySection.disabled(shell.workspaces.lastCreated != nil)
            }
            if shell.workspaces.source?.scm == .plastic {
                field("Branch") {
                    Picker("Branch", selection: binding(\.createNewBranch)) {
                        Text("Continue on current branch").tag(false)
                        Text("Create a new branch").tag(true)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(shell.workspaces.lastCreated != nil)
                }
            }
            advanced.disabled(shell.workspaces.lastCreated != nil)
            if let message = shell.workspaces.errorMessage {
                Text(message).font(Theme.Typography.labelMono).foregroundStyle(Theme.error)
            }
            if let message = shell.workspaces.warningMessage {
                Text(message).font(Theme.Typography.labelMono).foregroundStyle(Theme.warning)
            }
            HStack {
                Spacer(minLength: 0)
                Button("Cancel", action: dismiss).buttonStyle(.bordered)
                Button(shell.workspaces.phaseText) { shell.startWorkspaceCreation() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentVivid)
                    .disabled(!shell.workspaces.canCreate || shell.workspaces.isCreating)
            }
        }
        .disabled(shell.workspaces.isCreating)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title).font(Theme.Typography.labelMono).foregroundStyle(Theme.textSecondary)
            content()
        }
    }

    private func detected(_ source: WorkspaceSource) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Detected").font(Theme.Typography.labelMono).foregroundStyle(Theme.textSecondary)
            Text(source.scm == .none ? "Select a Git or Plastic SCM project to create a workspace." : "\(source.scm.title) detected · \(source.branch.isEmpty ? "detached HEAD" : source.branch)")
                .font(Theme.Typography.bodyMono).foregroundStyle(Theme.textPrimary)
        }
    }

    private var unitySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Unity project detected").font(Theme.Typography.labelMono).foregroundStyle(Theme.textSecondary)
            Text("Copying Library may shorten the first Unity import for CLI/MCP workflows.")
                .font(Theme.Typography.labelMono).foregroundStyle(Theme.textMuted)
            HStack(spacing: Theme.Spacing.sm) {
                LumiToggleSwitch(isOn: binding(\.copyLibrary), label: "Copy Library")
                Text("Copy Library").font(Theme.Typography.bodyMono).foregroundStyle(Theme.textPrimary)
            }
                .disabled(shell.workspaces.source?.hasLibrary != true || shell.workspaces.source?.libraryCopyBlockedReason != nil)
                .opacity(shell.workspaces.source?.hasLibrary == true && shell.workspaces.source?.libraryCopyBlockedReason == nil ? 1 : 0.45)
            if let reason = shell.workspaces.source?.libraryCopyBlockedReason {
                Text(reason).font(Theme.Typography.labelMono).foregroundStyle(Theme.textMuted)
            }
        }
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Destination: \(shell.workspaces.destinationPath)")
                .font(Theme.Typography.labelMono).foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Advanced", isExpanded: $isAdvancedExpanded) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    if shell.workspaces.createNewBranch {
                        Text("Branch name")
                            .font(Theme.Typography.labelMono).foregroundStyle(Theme.textSecondary)
                        LumiTextInput(
                            text: binding(\.branchName),
                            placeholder: shell.workspaces.source?.suggestedBranch(name: shell.workspaces.name) ?? "Branch name"
                        )
                    }
                    if let source = shell.workspaces.source, !source.revision.isEmpty {
                        Text("Base: \(source.revision)")
                            .font(Theme.Typography.labelMono).foregroundStyle(Theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(shell.workspaces.createNewBranch
                        ? "Starts from the current commit or changeset. Uncommitted changes are not copied."
                        : "Checks out the current branch in a separate workspace. Uncommitted changes are not copied.")
                        .font(Theme.Typography.labelMono).foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<ProjectWorkspaceStore, Value>) -> Binding<Value> {
        Binding(get: { shell.workspaces[keyPath: keyPath] }, set: { shell.workspaces[keyPath: keyPath] = $0 })
    }

    private func dismiss() {
        guard !shell.workspaces.isCreating else { return }
        shell.workspaces.clearForm()
        if let effectiveProjectPath {
            shell.dialogs.dismiss(.createWorkspace(projectPath: effectiveProjectPath))
        } else {
            shell.dialogs.dismiss()
        }
    }
}

private struct WorkspaceFormHeight: PreferenceKey {
    static let defaultValue: CGFloat = 1
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

#if DEBUG
#Preview("CreateWorkspaceOverlay") {
    CreateWorkspaceOverlay(projectPath: "/Users/preview/Projects/lumi")
        .environment(\.shell, ShellContext.preview())
        .frame(width: 800, height: 600)
}
#endif
