import LumiKit
import LumiState
import SwiftUI

public extension OverlayID {
    /// Tasks planı: task'i ajana verme sheet'i.
    static let startTask = OverlayID("startTask")
}

/// `Start with Claude…` sheet'i: proje → checkout (mevcut ya da task'e özel
/// yeni workspace) → model → prompt. Ajan normal, görünür bir terminalde
/// çalışır (Projects'te ve ızgarada görünür); işi bitirince `submit_for_review`
/// ile task'i kendisi In Review'a taşır.
public struct StartTaskOverlay: View {
    let store: TasksStore

    @Shell private var shell
    @State private var projectPath = ""
    @State private var checkout: CheckoutPick = .newWorkspace
    @State private var branch = ""
    @State private var model: ClaudeModelAlias?
    @State private var prompt = ""
    @State private var moveToInProgress = true
    @State private var assignToMe = true
    /// Lumi projelerinin git origin'leri — task'in `project.repo`'suyla eşleşme.
    @State private var origins: [String: String] = [:]
    /// Kullanıcı projeyi elle seçtiyse origin'ler gelince ezilmez.
    @State private var userPickedProject = false

    public init(store: TasksStore) {
        self.store = store
    }

    private enum CheckoutPick: Hashable {
        case existing(String)
        case newWorkspace
    }

    private static var panelWidth: CGFloat { Theme.scaled(640) }
    private static var panelHeight: CGFloat { Theme.scaled(680) }
    private static var promptHeight: CGFloat { Theme.scaled(150) }

    private var entry: TaskEntry? { store.startingTask.flatMap { store.entry($0) } }
    private var info: TaskSourceInfo? { entry.flatMap { store.info(of: $0.source) } }

    private var projectPaths: [String] { shell.workspaces.sidebarProjectPaths }

    private func projectName(_ path: String) -> String {
        shell.repos.repo(at: path)?.name ?? (path as NSString).lastPathComponent
    }

    private var isGitProject: Bool { shell.repos.repo(at: projectPath)?.isGitRepo == true }

    private var checkouts: [(path: String, label: String)] {
        guard !projectPath.isEmpty else { return [] }
        let root = (path: projectPath, label: "\(projectName(projectPath)) (main checkout)")
        let workspaces = shell.workspaces.workspaces(for: projectPath).map { (path: $0.path, label: "\($0.name) · \($0.branch)") }
        return [root] + workspaces
    }

    public var body: some View {
        ModalOverlay(onDismiss: store.cancelStart) {
            Panel(variant: .modal) {
                VStack(spacing: 0) {
                    header
                    Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
                    if let entry {
                        ScrollView(.vertical) { form(entry) .padding(Theme.Spacing.xxl) }
                    }
                    Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
                    footer
                }
            }
            .frame(width: Self.panelWidth, height: Self.panelHeight)
        }
        .onAppear(perform: prefill)
        .task {
            origins = await store.origins(for: projectPaths)
            guard !userPickedProject, let entry,
                  let matched = TaskProjectMatcher.match(entry.item.project, in: projectPaths, origins: origins)
            else { return }
            projectPath = matched
        }
        .onChange(of: projectPath) { _, path in
            // Proje değişince checkout seçimi o projeye göre yeniden kurulur.
            if case .existing(let current) = checkout, checkouts.contains(where: { $0.path == current }) { return }
            checkout = isGitProject ? .newWorkspace : .existing(path)
        }
    }

    // MARK: - Parçalar

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Start with Claude")
                    .font(Theme.Typography.mono(.headline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let entry {
                    Text("\(entry.item.id) · \(entry.item.title)")
                        .font(Theme.Typography.labelMono)
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer()
            IconButton(
                systemName: "xmark", label: "Close",
                side: Theme.scaled(28), cornerRadius: Theme.Radius.md, action: store.cancelStart
            )
        }
        .padding(Theme.Spacing.xl)
    }

    @ViewBuilder
    private func form(_ entry: TaskEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LumiField(title: "Project", hint: matchHint(entry)) {
                LumiDropdown(
                    options: projectPaths.map { .init(value: $0, label: projectName($0)) },
                    selection: Binding(get: { projectPath }, set: { projectPath = $0; userPickedProject = true }),
                    placeholder: "Choose a project",
                    emptyNote: "Add a project in the Projects panel first"
                )
            }
            LumiField(title: "Where", hint: "A new workspace keeps parallel tasks from touching each other") {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    LumiDropdown(options: checkoutOptions, selection: $checkout, placeholder: "Choose a checkout")
                        .disabled(projectPath.isEmpty)
                    if checkout == .newWorkspace {
                        LumiTextInput(text: $branch, placeholder: "task/branch-name")
                    }
                }
            }
            LumiField(title: "Model", hint: nil) {
                LumiDropdown(
                    options: [.init(value: ClaudeModelAlias?.none, label: "Default")]
                        + ClaudeModelAlias.allCases.map { .init(value: Optional($0), label: $0.displayName) },
                    selection: $model
                )
            }
            LumiField(title: "Prompt", hint: "Sent to Claude as the first message") {
                TextEditor(text: $prompt)
                    .font(Theme.Typography.bodyMono)
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Spacing.md)
                    .frame(height: Self.promptHeight)
                    .background(Theme.bgDeep)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.border, lineWidth: Theme.Stroke.hairline))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            VStack(spacing: Theme.Spacing.md) {
                LumiToggleRow(title: "Move to In Progress", hint: "When the agent starts", isOn: $moveToInProgress)
                if canAssignToMe(entry) {
                    LumiToggleRow(title: "Assign to me", hint: "The task is currently \(entry.item.assignee.map { "assigned to \($0.name)" } ?? "unassigned")", isOn: $assignToMe)
                }
            }
        }
    }

    private var checkoutOptions: [LumiDropdown<CheckoutPick>.Option] {
        var options: [LumiDropdown<CheckoutPick>.Option] = []
        if isGitProject {
            options.append(.init(value: .newWorkspace, label: "New workspace for this task", detail: "worktree"))
        }
        options += checkouts.map { .init(value: .existing($0.path), label: $0.label) }
        return options
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text("The agent opens as a normal terminal — you can watch and answer it from Projects.")
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textMuted)
                .lineLimit(2)
            Spacer()
            LumiActionButton(title: "Cancel", action: store.cancelStart)
            LumiActionButton(title: "Start", kind: .primary, action: start)
                .disabled(!canStart)
        }
        .padding(Theme.Spacing.xl)
    }

    // MARK: - Mantık

    private func matchHint(_ entry: TaskEntry) -> String? {
        guard let project = entry.item.project, info?.canRead(.project) == true else { return nil }
        return TaskProjectMatcher.match(project, in: projectPaths, origins: origins) == nil
            ? "No Lumi project matches \"\(project.displayName)\" — pick one"
            : "Matched from the task's project \"\(project.displayName)\""
    }

    private func canAssignToMe(_ entry: TaskEntry) -> Bool {
        guard let info, info.canAssign, let me = info.me else { return false }
        return entry.item.assignee?.id != me.id
    }

    private var canStart: Bool {
        guard !projectPath.isEmpty, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if checkout == .newWorkspace {
            return isGitProject && !branch.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }

    private func prefill() {
        guard let entry else { return }
        projectPath = TaskProjectMatcher.match(entry.item.project, in: projectPaths)
            ?? shell.navigation.activeRepoPath.flatMap { shell.navigation.projectPath(containing: $0) }
            ?? projectPaths.first ?? ""
        branch = TaskAgentPrompt.branchName(for: entry.item)
        checkout = isGitProject ? .newWorkspace : .existing(projectPath)
        prompt = TaskAgentPrompt.make(task: entry.item, includeBody: info?.canRead(.body) == true)
        assignToMe = canAssignToMe(entry)
    }

    private func start() {
        guard let entry, canStart else { return }
        let choice: TaskCheckoutChoice = switch checkout {
        case .existing(let path): .existing(path: path)
        case .newWorkspace: .newWorkspace(projectPath: projectPath, branch: branch.trimmingCharacters(in: .whitespaces))
        }
        store.start(
            TaskAgentRequest(
                task: entry.key, taskTitle: entry.item.title, checkout: choice,
                agent: TaskAgentChoice(model: model), prompt: prompt,
                details: store.agentDetails(for: entry.key)
            ),
            moveToInProgress: moveToInProgress,
            assignToMe: assignToMe && canAssignToMe(entry)
        )
    }
}
