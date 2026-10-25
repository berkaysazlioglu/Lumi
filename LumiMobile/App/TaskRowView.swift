import SwiftUI
import LumiMobileKit

/// One task on the phone's board: status, title, a quiet meta line (id ·
/// priority · project · age), the assignee and — if an agent works on it —
/// its state (Projects' glyph language).
struct TaskRowView: View {
    let task: RemoteTask
    let me: TaskUserRef?
    var showsSource = false
    var sourceName: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            TaskStatusGlyph(status: task.status)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(task.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(task.status == .done ? .secondary : .primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if let assignee = task.assignee {
                        TaskAvatarView(user: assignee, isMe: assignee.id == me?.id)
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    }
                }
                meta
                if let agent = task.agent {
                    TaskAgentBadge(agent: agent)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var meta: some View {
        HStack(spacing: 6) {
            if task.needsAttention {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .accessibilityLabel("Needs attention")
            }
            Text(task.id).monospaced()
            if let priority = task.priority, priority != "none" {
                TaskPriorityGlyph(priority: priority)
            }
            ForEach(details, id: \.self) { part in
                Text("·").foregroundStyle(.tertiary)
                Text(part)
            }
            if task.imageCount > 0 {
                Image(systemName: "photo").accessibilityLabel("\(task.imageCount) images")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var details: [String] {
        [
            task.project?.displayName,
            showsSource ? sourceName : nil,
            task.labels.first,
            TaskDates.short(task.updatedAt),
        ].compactMap { $0 }
    }
}

/// `updatedAt` (ms since 1970) as the board and the detail show it.
enum TaskDates {
    static func date(_ milliseconds: Double) -> Date? {
        milliseconds > 0 ? Date(timeIntervalSince1970: milliseconds / 1000) : nil
    }

    /// `5m`, `3h`, `2d` — the row's meta line.
    static func short(_ milliseconds: Double) -> String? {
        guard let date = date(milliseconds) else { return nil }
        let seconds = max(0, Date().timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        case ..<(86_400 * 30): return "\(Int(seconds / 86_400))d"
        default: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    /// `Updated 2 hours ago` — the detail's header.
    static func relative(_ milliseconds: Double) -> String? {
        date(milliseconds).map { "Updated " + $0.formatted(.relative(presentation: .named)) }
    }
}

/// `● In Progress` on a tinted capsule — the detail's header.
struct TaskStatusPill: View {
    let status: RemoteTaskStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: TaskStatusGlyph.icon(status))
            Text(status.title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(TaskStatusGlyph.color(status))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(TaskStatusGlyph.color(status).opacity(0.14), in: Capsule())
    }
}

/// `↑ High` on a tinted capsule — the detail's header.
struct TaskPriorityPill: View {
    let priority: String

    var body: some View {
        HStack(spacing: 4) {
            TaskPriorityGlyph(priority: priority)
            Text(priority.capitalized)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(TaskPriorityGlyph.color(priority))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(TaskPriorityGlyph.color(priority).opacity(0.14), in: Capsule())
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
            .foregroundStyle(Self.color(priority))
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

    static func color(_ priority: String) -> Color {
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
