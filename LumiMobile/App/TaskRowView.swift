import SwiftUI
import LumiMobileKit

/// One task on the phone's board: status, id, title, priority, assignee and
/// — if an agent works on it — its state (Projects' glyph language).
struct TaskRowView: View {
    let task: RemoteTask
    let me: TaskUserRef?
    var showsSource = false
    var sourceName: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            TaskStatusGlyph(status: task.status)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(task.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                    if task.needsAttention {
                        Text("Needs attention").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                    }
                    if let priority = task.priority, priority != "none" {
                        TaskPriorityGlyph(priority: priority)
                    }
                    Spacer(minLength: 0)
                    if let assignee = task.assignee {
                        TaskAvatarView(user: assignee, isMe: assignee.id == me?.id)
                    }
                }
                Text(task.title)
                    .font(.body)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                if let agent = task.agent {
                    TaskAgentBadge(agent: agent)
                }
                meta
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var meta: some View {
        let parts = [
            task.project?.displayName,
            showsSource ? sourceName : nil,
            task.imageCount > 0 ? "\(task.imageCount) image\(task.imageCount == 1 ? "" : "s")" : nil,
            task.labels.isEmpty ? nil : task.labels.prefix(2).joined(separator: ", "),
        ].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct TaskStatusGlyph: View {
    let status: RemoteTaskStatus

    var body: some View {
        Image(systemName: Self.icon(status))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Self.color(status))
            .accessibilityLabel(status.title)
    }

    static func icon(_ status: RemoteTaskStatus) -> String {
        switch status {
        case .todo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .inReview: "eye.circle"
        case .done: "checkmark.circle.fill"
        }
    }

    static func color(_ status: RemoteTaskStatus) -> Color {
        switch status {
        case .todo: .secondary
        case .inProgress: .orange
        case .inReview: LumiPalette.accent
        case .done: .green
        }
    }
}

struct TaskPriorityGlyph: View {
    let priority: String

    var body: some View {
        Image(systemName: icon)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .accessibilityLabel("Priority \(priority)")
    }

    private var icon: String {
        switch priority {
        case "urgent": "exclamationmark.2"
        case "high": "chevron.up"
        case "medium": "equal"
        default: "chevron.down"
        }
    }

    private var color: Color {
        switch priority {
        case "urgent": .red
        case "high": .orange
        case "medium": .cyan
        default: .secondary
        }
    }
}

struct TaskAvatarView: View {
    let user: TaskUserRef
    let isMe: Bool

    var body: some View {
        Text(user.initials)
            .font(.system(size: 9, weight: .bold))
            .frame(width: 20, height: 20)
            .background(isMe ? LumiPalette.accent : LumiPalette.elevated, in: Circle())
            .foregroundStyle(isMe ? .white : .secondary)
            .accessibilityLabel(isMe ? "Assigned to you" : "Assigned to \(user.name)")
    }
}

/// `✦ Claude Opus · Working` — the agent's state on the row and in the detail.
struct TaskAgentBadge: View {
    let agent: RemoteTaskAgent

    var body: some View {
        HStack(spacing: 5) {
            glyph
            Text("\(agent.title) · \(agent.state.title)")
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }

    @ViewBuilder private var glyph: some View {
        switch agent.state {
        case .starting, .working: ProgressView().controlSize(.mini).tint(color)
        case .needsInput: Image(systemName: "bell.fill").font(.caption2).foregroundStyle(color)
        case .idle: Image(systemName: "pause.circle").font(.caption2).foregroundStyle(color)
        case .submitted: Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(color)
        case .exited: Image(systemName: "stop.circle").font(.caption2).foregroundStyle(color)
        }
    }

    private var color: Color {
        switch agent.state {
        case .starting, .working: .green
        case .needsInput: .orange
        case .idle, .exited: .secondary
        case .submitted: LumiPalette.accent
        }
    }
}
