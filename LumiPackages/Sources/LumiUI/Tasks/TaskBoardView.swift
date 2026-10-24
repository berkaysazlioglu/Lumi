import LumiKit
import LumiState
import SwiftUI

/// Dört kolonlu Board (Tasks planı, kullanıcı kararı 1). Kart kolonlar arası
/// sürüklenince durum iyimser olarak değişir.
struct TaskBoardView: View {
    let store: TasksStore

    private static var columnMinWidth: CGFloat { Theme.scaled(220) }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            ForEach(store.columns) { column in
                TaskBoardColumn(store: store, column: column)
                    .frame(minWidth: Self.columnMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(Theme.Spacing.xl)
    }
}

private struct TaskBoardColumn: View {
    let store: TasksStore
    let column: TaskBoard.Column

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header
            ScrollView(.vertical) {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(column.entries) { entry in
                        TaskCardView(store: store, entry: entry)
                    }
                    if column.hiddenCount > 0 {
                        Button("Show \(column.hiddenCount) more") { store.showAllDone = true }
                            .buttonStyle(HoverButtonStyle(foreground: Theme.textMuted))
                            .font(Theme.Typography.labelMono)
                            .padding(.vertical, Theme.Spacing.sm)
                    }
                    if column.entries.isEmpty {
                        Text(isTargeted ? "Drop here" : "No tasks")
                            .font(Theme.Typography.labelMono)
                            .foregroundStyle(Theme.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.xxl)
                    }
                }
                .padding(Theme.Spacing.xxs)
            }
        }
        .padding(Theme.Spacing.md)
        .background(isTargeted ? Theme.bgElevated : Theme.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(isTargeted ? TaskPresentation.color(column.status) : Theme.border, lineWidth: Theme.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .dropDestination(for: String.self) { payloads, _ in
            let keys = payloads.compactMap(TaskKey.init(transferValue:))
            guard !keys.isEmpty else { return false }
            for key in keys {
                Task { await store.move(key, to: column.status) }
            }
            return true
        } isTargeted: { isTargeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(column.status.title), \(column.totalCount) tasks")
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            TaskStatusIcon(status: column.status)
            Text(column.status.title)
                .font(Theme.Typography.mono(.body, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("\(column.totalCount)")
                .font(Theme.Typography.mono(.label))
                .foregroundStyle(Theme.textMuted)
                .monospacedDigit()
            Spacer(minLength: 0)
            if column.status == .done, store.showAllDone, column.totalCount > TaskBoard.doneLimit {
                Button("Show recent") { store.showAllDone = false }
                    .buttonStyle(HoverButtonStyle(foreground: Theme.textMuted))
                    .font(Theme.Typography.captionMono)
            }
            if store.creatableSources.isEmpty == false {
                IconButton(systemName: "plus", label: "New task in \(column.status.title)") {
                    store.beginNewTask(status: column.status)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
    }
}

/// Board kartı. Yalnız kaynağın okuyabildiği alanlar çizilir.
struct TaskCardView: View {
    let store: TasksStore
    let entry: TaskEntry

    private var item: TaskItem { entry.item }
    private var info: TaskSourceInfo? { store.info(of: entry.source) }
    private var isSelected: Bool { store.selectedTask == entry.key }
    private var showsSource: Bool { store.filter.source == nil && store.sources.count > 1 }

    var body: some View {
        HoverReader { isHovering in
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(item.id)
                        .font(Theme.Typography.mono(.caption))
                        .foregroundStyle(Theme.textMuted)
                    if item.needsAttention { TaskAttentionBadge() }
                    Spacer(minLength: 0)
                    if info?.canRead(.priority) == true, let priority = item.priority, priority != .none {
                        TaskPriorityIcon(priority: priority)
                    }
                }
                Text(item.title)
                    .font(Theme.Typography.ui(.body, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if info?.canRead(.labels) == true, !item.labels.isEmpty {
                    labels
                }
                footer
            }
            .padding(Theme.Spacing.lg)
            .background(isHovering || isSelected ? Theme.bgElevated : Theme.bgDeep)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(isSelected ? Theme.accentVivid : Theme.border.opacity(0.6), lineWidth: Theme.Stroke.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .contentShape(Rectangle())
            .onTapGesture { store.selectedTask = isSelected ? nil : entry.key }
            .draggable(entry.key.transferValue) {
                Text(item.title)
                    .font(Theme.Typography.bodyMono)
                    .padding(Theme.Spacing.md)
                    .background(Theme.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var labels: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(item.labels.prefix(2), id: \.self) { label in
                Badge(text: label, color: Theme.accentCyan, shape: .capsule)
            }
            if item.labels.count > 2 {
                Text("+\(item.labels.count - 2)")
                    .font(Theme.Typography.mono(.caption))
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if info?.canRead(.project) == true, let project = item.project {
                TaskProjectChip(project: project)
            }
            if showsSource, let source = store.state(of: entry.source) {
                Text(source.source.name)
                    .font(Theme.Typography.mono(.caption))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if info?.canRead(.dueDate) == true, let due = item.dueDate {
                Label(TaskPresentation.day(due), systemImage: "calendar")
                    .font(Theme.Typography.mono(.caption))
                    .foregroundStyle(Theme.textMuted)
                    .labelStyle(.titleAndIcon)
            }
            if info?.canRead(.assignee) == true, let assignee = item.assignee {
                TaskAvatar(user: assignee, isMe: assignee.id == info?.me?.id)
            }
        }
    }
}
