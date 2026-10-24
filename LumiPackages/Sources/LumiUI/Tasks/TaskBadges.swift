import LumiKit
import SwiftUI

/// Durum, öncelik ve kişi için ortak görsel dil (Tasks planı, Faz 1).
enum TaskPresentation {
    static func color(_ status: TaskStatus) -> Color {
        switch status {
        case .todo: Theme.textSecondary
        case .inProgress: Theme.warning
        case .inReview: Theme.accentPrimary
        case .done: Theme.success
        }
    }

    static func icon(_ status: TaskStatus) -> String {
        switch status {
        case .todo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .inReview: "eye.circle"
        case .done: "checkmark.circle.fill"
        }
    }

    static func color(_ priority: TaskPriority) -> Color {
        switch priority {
        case .none: Theme.textMuted
        case .low: Theme.textSecondary
        case .medium: Theme.ice
        case .high: Theme.warning
        case .urgent: Theme.error
        }
    }

    static func icon(_ priority: TaskPriority) -> String {
        switch priority {
        case .none: "minus"
        case .low: "chevron.down"
        case .medium: "equal"
        case .high: "chevron.up"
        case .urgent: "exclamationmark.2"
        }
    }

    /// "5 min ago" biçimi — başlık şeridi ve detay.
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 10 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct TaskStatusIcon: View {
    let status: TaskStatus
    var size: Theme.Typography.Size = .label

    var body: some View {
        Image(systemName: TaskPresentation.icon(status))
            .font(Theme.Typography.ui(size, weight: .semibold))
            .foregroundStyle(TaskPresentation.color(status))
            .accessibilityLabel(status.title)
    }
}

struct TaskPriorityIcon: View {
    let priority: TaskPriority

    var body: some View {
        Image(systemName: TaskPresentation.icon(priority))
            .font(Theme.Typography.ui(.caption, weight: .bold))
            .foregroundStyle(TaskPresentation.color(priority))
            .frame(width: Theme.Row.iconColumn)
            .help("Priority: \(priority.title)")
            .accessibilityLabel("Priority \(priority.title)")
    }
}

/// Atanan kişinin baş harfli yuvarlağı.
struct TaskAvatar: View {
    let user: TaskUser
    var isMe = false

    private static var side: CGFloat { Theme.scaled(18) }

    var body: some View {
        Text(user.initials)
            .font(Theme.Typography.ui(.micro, weight: .bold))
            .foregroundStyle(isMe ? Theme.textPrimary : Theme.textSecondary)
            .frame(width: Self.side, height: Self.side)
            .background(Circle().fill(isMe ? Theme.accentVivid : Theme.bgElevated))
            .overlay(Circle().stroke(Theme.border, lineWidth: Theme.Stroke.hairline))
            .help(isMe ? "\(user.name) (you)" : user.name)
            .accessibilityLabel(isMe ? "Assigned to you" : "Assigned to \(user.name)")
    }
}

/// Projenin adı — renk eşleşmesi Faz 3'te Lumi projesinden gelir.
struct TaskProjectChip: View {
    let project: TaskProjectRef

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "folder")
                .font(Theme.Typography.ui(.micro))
                .accessibilityHidden(true)
            Text(project.displayName)
                .lineLimit(1)
        }
        .font(Theme.Typography.mono(.caption))
        .foregroundStyle(Theme.textSecondary)
    }
}

/// Sunucunun bozuk gönderdiği task'in uyarısı.
struct TaskAttentionBadge: View {
    var body: some View {
        Badge(text: "Needs attention", color: Theme.warning)
            .help("The server sent an unknown status or a broken field. Moving the task writes a valid status.")
    }
}

/// Başlık şeridi ve detaydaki menülü buton: etiket + chevron, tıklayınca
/// `PopoverMenu` açılır.
struct TaskMenuButton<Label: View>: View {
    let items: () -> [PopoverMenu.Item]
    var isEnabled = true
    @ViewBuilder let label: () -> Label

    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: Theme.Spacing.xs) {
                label()
                if isEnabled {
                    Image(systemName: "chevron.down")
                        .font(Theme.Typography.ui(.micro, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Row.control)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverButtonStyle(foreground: Theme.textSecondary, hoverBackground: isEnabled ? Theme.bgElevated : .clear))
        .disabled(!isEnabled)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            PopoverMenu(items: items(), dismiss: { isOpen = false })
        }
    }
}
