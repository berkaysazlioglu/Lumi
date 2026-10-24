import LumiKit
import LumiState
import SwiftUI

/// Yeni task sheet'i. Alanlar seçili kaynağın yazabildikleriyle sınırlıdır.
public extension OverlayID {
    /// Tasks planı: kaynak bağlama ve yeni task sheet'leri.
    static let taskConnect = OverlayID("taskConnect")
    static let newTask = OverlayID("newTask")
}

public struct NewTaskOverlay: View {
    @Bindable var store: TasksStore

    public init(store: TasksStore) {
        self.store = store
    }

    private static var panelWidth: CGFloat { Theme.scaled(560) }

    private var form: NewTaskForm? { store.newTaskForm }
    private var sourceState: TasksStore.SourceState? { form.flatMap { store.state(of: $0.source) } }
    private var info: TaskSourceInfo? { sourceState?.info }

    public var body: some View {
        ModalOverlay(onDismiss: store.cancelNewTask) {
            Panel(variant: .modal) {
                VStack(spacing: 0) {
                    header
                    Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        LumiTextInput(
                            text: text(\.title), placeholder: "Task title", autofocus: true,
                            onSubmit: { Task { await store.submitNewTask() } }
                        )
                        if info?.canWrite(.body) == true {
                            TextField("Description (markdown)", text: text(\.body), axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(Theme.Typography.bodyMono)
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(4...10)
                                .padding(Theme.Spacing.lg)
                                .background(Theme.bgDeep)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                                        .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                        }
                        properties
                    }
                    .padding(Theme.Spacing.xl)
                    Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
                    footer
                }
            }
            .frame(width: Self.panelWidth)
        }
    }

    private func text(_ path: WritableKeyPath<NewTaskForm, String>) -> Binding<String> {
        Binding(
            get: { store.newTaskForm?[keyPath: path] ?? "" },
            set: { store.newTaskForm?[keyPath: path] = $0 }
        )
    }

    private var header: some View {
        HStack {
            Text("New Task")
                .font(Theme.Typography.mono(.headline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            IconButton(
                systemName: "xmark", label: "Close",
                side: Theme.scaled(28), cornerRadius: Theme.Radius.md, action: store.cancelNewTask
            )
        }
        .padding(Theme.Spacing.xl)
    }

    // MARK: - Özellik menüleri

    private var properties: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if store.creatableSources.count > 1 { sourceMenu }
            statusMenu
            if info?.canWrite(.project) == true, let projects = sourceState?.projects, !projects.isEmpty {
                projectMenu(projects)
            }
            if info?.canWrite(.priority) == true { priorityMenu }
            if info?.canAssign == true { assigneeMenu }
            Spacer(minLength: 0)
        }
    }

    private var sourceMenu: some View {
        TaskMenuButton(items: {
            store.creatableSources.map { state in
                .toggle(state.source.name, isOn: form?.source == state.id) { store.selectNewTaskSource(state.id) }
            }
        }) {
            Image(systemName: "tray.full").font(Theme.Typography.ui(.label)).accessibilityHidden(true)
            Text(sourceState?.source.name ?? "Source").font(Theme.Typography.labelMono)
        }
    }

    private var statusMenu: some View {
        let status = form?.status ?? .todo
        return TaskMenuButton(items: {
            TaskStatus.allCases.map { option in
                .toggle(option.title, isOn: option == status) { store.newTaskForm?.status = option }
            }
        }) {
            TaskStatusIcon(status: status)
            Text(status.title).font(Theme.Typography.labelMono)
        }
    }

    private func projectMenu(_ projects: [TaskProjectRef]) -> some View {
        let selected = projects.first { $0.key == form?.projectKey }
        return TaskMenuButton(items: {
            [.toggle("No project", isOn: form?.projectKey == nil) { store.newTaskForm?.projectKey = nil }, .divider]
                + projects.map { project in
                    .toggle(project.displayName, isOn: form?.projectKey == project.key) {
                        store.newTaskForm?.projectKey = project.key
                    }
                }
        }) {
            Image(systemName: "folder").font(Theme.Typography.ui(.label)).accessibilityHidden(true)
            Text(selected?.displayName ?? "Project").font(Theme.Typography.labelMono)
        }
    }

    private var priorityMenu: some View {
        let priority = form?.priority ?? .none
        return TaskMenuButton(items: {
            TaskPriority.allCases.reversed().map { option in
                .toggle(option.title, isOn: option == priority) { store.newTaskForm?.priority = option }
            }
        }) {
            TaskPriorityIcon(priority: priority)
            Text(priority == .none ? "Priority" : priority.title).font(Theme.Typography.labelMono)
        }
    }

    private var assigneeMenu: some View {
        let options = form.map { store.assignOptions(for: $0.source) } ?? []
        let selected = form?.assignee
        return TaskMenuButton(items: {
            var items: [PopoverMenu.Item] = options.map { option in
                .toggle(option.title, isOn: option.user.id == selected?.id) { store.newTaskForm?.assignee = option.user }
            }
            items.append(.divider)
            items.append(.toggle("Unassigned", isOn: selected == nil) { store.newTaskForm?.assignee = nil })
            return items
        }) {
            if let selected {
                TaskAvatar(user: selected, isMe: selected.id == info?.me?.id)
                Text(selected.id == info?.me?.id ? "You" : selected.name).font(Theme.Typography.labelMono)
            } else {
                Image(systemName: "person").font(Theme.Typography.ui(.label)).accessibilityHidden(true)
                Text("Assignee").font(Theme.Typography.labelMono)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            Spacer()
            LumiActionButton(title: "Cancel", action: store.cancelNewTask)
            LumiActionButton(title: form?.isSubmitting == true ? "Creating…" : "Create Task", kind: .primary) {
                Task { await store.submitNewTask() }
            }
            .disabled(form?.canSubmit != true)
        }
        .padding(Theme.Spacing.xl)
    }
}
