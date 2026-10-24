import LumiKit
import LumiState
import SwiftUI

/// List görünümü: aynı veri tek kolonlu tablo olarak. Kolonlar yalnız görünen
/// kaynaklardan biri o alanı okuyabiliyorsa çizilir.
struct TaskListView: View {
    let store: TasksStore

    private static var projectWidth: CGFloat { Theme.scaled(140) }
    private static var assigneeWidth: CGFloat { Theme.scaled(130) }
    private static var updatedWidth: CGFloat { Theme.scaled(90) }
    private static var statusWidth: CGFloat { Theme.scaled(110) }

    private var showsPriority: Bool { store.anyVisibleSourceCanRead(.priority) }
    private var showsProject: Bool { store.anyVisibleSourceCanRead(.project) }
    private var showsAssignee: Bool { store.anyVisibleSourceCanRead(.assignee) }

    var body: some View {
        let rows = store.rows
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
            if rows.isEmpty {
                EmptyStatePlaceholder("No tasks match", density: .full)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { entry in
                            row(entry)
                        }
                    }
                }
            }
        }
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg).stroke(Theme.border, lineWidth: Theme.Stroke.hairline))
        .padding(Theme.Spacing.xl)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Text("Status").frame(width: Self.statusWidth, alignment: .leading)
            Text("Title").frame(maxWidth: .infinity, alignment: .leading)
            if showsProject { Text("Project").frame(width: Self.projectWidth, alignment: .leading) }
            if showsAssignee { Text("Assignee").frame(width: Self.assigneeWidth, alignment: .leading) }
            Text("Updated").frame(width: Self.updatedWidth, alignment: .trailing)
        }
        .font(Theme.Typography.ui(.caption, weight: .semibold))
        .foregroundStyle(Theme.textMuted)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    private func row(_ entry: TaskEntry) -> some View {
        let item = entry.item
        let info = store.info(of: entry.source)
        let isSelected = store.selectedTask == entry.key
        return HoverReader { isHovering in
            HStack(spacing: Theme.Spacing.lg) {
                HStack(spacing: Theme.Spacing.sm) {
                    TaskStatusIcon(status: item.status)
                    Text(item.status.title)
                        .font(Theme.Typography.labelMono)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(width: Self.statusWidth, alignment: .leading)
                HStack(spacing: Theme.Spacing.sm) {
                    if showsPriority {
                        if info?.canRead(.priority) == true, let priority = item.priority {
                            TaskPriorityIcon(priority: priority)
                        } else {
                            Color.clear.frame(width: Theme.Row.iconColumn)
                        }
                    }
                    Text(item.id)
                        .font(Theme.Typography.mono(.caption))
                        .foregroundStyle(Theme.textMuted)
                    Text(item.title)
                        .font(Theme.Typography.ui(.body))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if item.needsAttention { TaskAttentionBadge() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if showsProject {
                    Group {
                        if info?.canRead(.project) == true, let project = item.project {
                            TaskProjectChip(project: project)
                        } else {
                            Text("—").foregroundStyle(Theme.textMuted)
                        }
                    }
                    .frame(width: Self.projectWidth, alignment: .leading)
                }
                if showsAssignee {
                    assigneeCell(item.assignee, info: info)
                        .frame(width: Self.assigneeWidth, alignment: .leading)
                }
                Text(TaskPresentation.relative(item.updatedAt))
                    .font(Theme.Typography.mono(.caption))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: Self.updatedWidth, alignment: .trailing)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(height: Theme.Row.commit)
            .background(isSelected ? Theme.bgElevated : (isHovering ? Theme.bgElevated.opacity(0.6) : .clear))
            .contentShape(Rectangle())
            .onTapGesture { store.selectedTask = isSelected ? nil : entry.key }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func assigneeCell(_ user: TaskUser?, info: TaskSourceInfo?) -> some View {
        if info?.canRead(.assignee) == true, let user {
            HStack(spacing: Theme.Spacing.sm) {
                TaskAvatar(user: user, isMe: user.id == info?.me?.id)
                Text(user.id == info?.me?.id ? "You" : user.name)
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        } else {
            Text("—")
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textMuted)
        }
    }
}
