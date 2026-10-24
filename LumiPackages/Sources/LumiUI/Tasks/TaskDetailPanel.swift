import AppKit
import LumiKit
import LumiState
import SwiftUI

/// Seçili task'in sağdaki detay çekmecesi. Her satır kaynağın beyanına
/// bağlıdır: okunamayan alan hiç çizilmez, yazılamayan alan menüsüz durur.
struct TaskDetailPanel: View {
    let store: TasksStore
    let entry: TaskEntry

    @Shell private var shell
    @State private var titleDraft = ""
    @State private var confirmsDelete = false

    static var width: CGFloat { Theme.scaled(380) }
    private static var labelWidth: CGFloat { Theme.scaled(84) }

    private var item: TaskItem { entry.item }
    private var info: TaskSourceInfo? { store.info(of: entry.source) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    titleField
                    if item.needsAttention { TaskAttentionBadge() }
                    properties
                    TaskAgentSection(store: store, entry: entry)
                    images
                    description
                }
                .padding(Theme.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
            footer
        }
        .frame(width: Self.width)
        .background(Theme.bgSurface)
        .onChange(of: item.title, initial: true) { _, title in titleDraft = title }
        .onChange(of: entry.key) { _, _ in confirmsDelete = false }
    }

    // MARK: - Başlık

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(item.id)
                .font(Theme.Typography.mono(.label, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            if info?.canRead(.url) == true, let url = item.url {
                IconButton(systemName: "arrow.up.right.square", label: "Open in Browser", side: Theme.scaled(24)) {
                    shell.actions.openURL(url)
                }
            }
            IconButton(systemName: "xmark", label: "Close details", side: Theme.scaled(24)) {
                store.selectedTask = nil
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: Theme.Row.commit)
    }

    private var titleField: some View {
        TextField("Title", text: $titleDraft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(Theme.Typography.ui(.title, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1...4)
            .onSubmit(commitTitle)
            .onExitCommand { titleDraft = item.title }
            .accessibilityLabel("Task title")
    }

    private func commitTitle() {
        let key = entry.key
        let draft = titleDraft
        store.rename(key, to: draft)
    }

    // MARK: - Özellikler

    private var properties: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            property("Status") { statusMenu }
            if info?.canRead(.assignee) == true {
                property("Assignee") { assigneeMenu }
            }
            if info?.canRead(.priority) == true {
                property("Priority") { priorityMenu }
            }
            if info?.canRead(.project) == true, let project = item.project {
                property("Project") { TaskProjectChip(project: project).padding(.horizontal, Theme.Spacing.md) }
            }
            if info?.canRead(.labels) == true, !item.labels.isEmpty {
                property("Labels") {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(item.labels, id: \.self) {
                            Badge(text: $0, color: Theme.accentCyan, shape: .capsule)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                }
            }
            if info?.canRead(.dueDate) == true, let due = item.dueDate {
                property("Due") { plain(TaskPresentation.day(due)) }
            }
            if store.sources.count > 1, let source = store.state(of: entry.source) {
                property("Source") { plain(source.source.name) }
            }
            property("Updated") { plain(TaskPresentation.relative(item.updatedAt)) }
        }
    }

    private func property<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textMuted)
                .frame(width: Self.labelWidth, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .frame(minHeight: Theme.Row.control)
    }

    private func plain(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.labelMono)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
    }

    private var statusMenu: some View {
        TaskMenuButton(items: {
            TaskStatus.allCases.map { status in
                .action(status.title, icon: TaskPresentation.icon(status), isEnabled: status != item.status || item.needsAttention) {
                    let key = entry.key
                    store.move(key, to: status)
                }
            }
        }) {
            TaskStatusIcon(status: item.status)
            Text(item.status.title).font(Theme.Typography.labelMono)
        }
    }

    private var assigneeMenu: some View {
        let options = store.assignOptions(for: entry.source)
        let me = info?.me
        return TaskMenuButton(items: {
            var items: [PopoverMenu.Item] = options.map { option in
                .action(option.title, icon: option.user.id == item.assignee?.id ? "checkmark" : nil) {
                    let key = entry.key
                    store.assign(key, to: option.user)
                }
            }
            items.append(.divider)
            items.append(.action("Unassigned", icon: item.assignee == nil ? "checkmark" : nil) {
                let key = entry.key
                store.assign(key, to: nil)
            })
            return items
        }, isEnabled: info?.canAssign == true) {
            if let assignee = item.assignee {
                TaskAvatar(user: assignee, isMe: assignee.id == me?.id)
                Text(assignee.id == me?.id ? "You" : assignee.name)
                    .font(Theme.Typography.labelMono)
                    .lineLimit(1)
            } else {
                Text("Unassigned").font(Theme.Typography.labelMono).foregroundStyle(Theme.textMuted)
            }
        }
        .help(info?.canAssign == true ? "Assign" : "This source doesn't allow assigning from Lumi")
    }

    private var priorityMenu: some View {
        let priority = item.priority ?? .none
        return TaskMenuButton(items: {
            TaskPriority.allCases.reversed().map { option in
                .action(option.title, icon: TaskPresentation.icon(option), isEnabled: option != priority) {
                    let key = entry.key
                    store.setPriority(key, to: option)
                }
            }
        }, isEnabled: info?.canWrite(.priority) == true) {
            TaskPriorityIcon(priority: priority)
            Text(priority.title).font(Theme.Typography.labelMono)
        }
    }

    // MARK: - Görseller

    @ViewBuilder
    private var images: some View {
        if info?.canRead(.images) == true, !item.images.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("IMAGES · \(item.images.count)")
                    .font(Theme.Typography.ui(.caption, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                TaskImageStrip(store: store, entry: entry)
            }
        }
    }

    // MARK: - Açıklama

    @ViewBuilder
    private var description: some View {
        if info?.canRead(.body) == true {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("DESCRIPTION")
                    .font(Theme.Typography.ui(.caption, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                if let body = item.body, !body.isEmpty {
                    MarkdownBlocksView(
                        blocks: shell.markdownParser.parse(body).blocks,
                        context: MarkdownRenderContext(highlighter: shell.highlighter, size: .body)
                    )
                    .textSelection(.enabled)
                } else {
                    Text("No description")
                        .font(Theme.Typography.labelMono)
                        .foregroundStyle(Theme.textMuted)
                }
            }
        }
    }

    // MARK: - Alt bar

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            LumiActionButton(title: "Copy as Prompt") { copyAsPrompt() }
                .help("Copy the task as a prompt to paste into an agent")
            Spacer(minLength: 0)
            if info?.supports(.delete) == true {
                if confirmsDelete {
                    LumiActionButton(title: "Cancel") { confirmsDelete = false }
                    LumiActionButton(title: "Delete", kind: .destructive) {
                        let key = entry.key
                        confirmsDelete = false
                        Task { await store.delete(key) }
                    }
                } else {
                    IconButton(systemName: "trash", label: "Delete task", side: Theme.scaled(28), role: .destructive) {
                        confirmsDelete = true
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
    }

    private func copyAsPrompt() {
        let text = store.copyPrompt(for: entry.key)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        shell.toasts.show(.success, title: "Copied task as prompt")
    }
}
