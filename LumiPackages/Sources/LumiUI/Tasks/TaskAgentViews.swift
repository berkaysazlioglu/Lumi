import LumiKit
import LumiState
import SwiftUI

/// Ajan durumunun ortak görsel dili — Projects ajan satırının sezgileriyle
/// aynı yönde: çalışıyor yeşil, karar bekliyor sarı, teslim mor.
enum TaskAgentPresentation {
    static func color(_ state: TaskAgentState) -> Color {
        switch state {
        case .starting, .working: Theme.success
        case .needsInput: Theme.warning
        case .idle: Theme.textSecondary
        case .submitted: Theme.accentPrimary
        case .exited: Theme.textMuted
        }
    }

    static func icon(_ state: TaskAgentState) -> String {
        switch state {
        case .starting: "hourglass"
        case .working: "sparkles"
        case .needsInput: "bell.fill"
        case .idle: "pause.circle"
        case .submitted: "checkmark.seal.fill"
        case .exited: "stop.circle"
        }
    }
}

/// Karttaki ajan çipi: `✦ Claude Opus · Working`.
struct TaskAgentChip: View {
    let link: TaskAgentLink

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: TaskAgentPresentation.icon(link.state))
                .font(Theme.Typography.ui(.caption, weight: .semibold))
                .symbolEffect(.pulse, isActive: link.state == .working || link.state == .starting)
                .accessibilityHidden(true)
            Text("\(link.agent.title) · \(link.state.title)")
                .lineLimit(1)
        }
        .font(Theme.Typography.mono(.caption, weight: .medium))
        .foregroundStyle(TaskAgentPresentation.color(link.state))
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xxs)
        .background(TaskAgentPresentation.color(link.state).opacity(0.12))
        .clipShape(Capsule())
        .accessibilityLabel("Agent \(link.agent.title), \(link.state.title)")
    }
}

/// Detaydaki ajan bölümü: bağlantı yoksa `Start`, varsa durum + eylemler.
struct TaskAgentSection: View {
    let store: TasksStore
    let entry: TaskEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Text("AGENT")
                    .font(Theme.Typography.ui(.caption, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                if store.isAgentPreview {
                    Badge(text: "Preview", color: Theme.warning)
                        .help("No real terminal runs yet — this simulates the flow. Real agents arrive in phase 3.")
                }
            }
            if let link = store.agentLink(for: entry.key) {
                linked(link)
            } else {
                LumiActionButton(title: "▶  Start with Claude…", kind: .primary) { store.beginStart(entry.key) }
                    .help("Open an agent terminal in this task's project and hand it the task")
            }
        }
    }

    @ViewBuilder
    private func linked(_ link: TaskAgentLink) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            TaskAgentChip(link: link)
            Text("in \(link.checkout.label) · started \(TaskPresentation.relative(link.startedAt))")
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textMuted)
            if case .submitted(let summary) = link.state {
                Text(summary)
                    .font(Theme.Typography.bodyMono)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bgDeep)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            HStack(spacing: Theme.Spacing.sm) {
                LumiActionButton(title: "Open Terminal") {}
                    .disabled(link.terminalID == nil)
                    .help(link.terminalID == nil ? "Preview — there is no real terminal yet" : "Show the agent's terminal")
                // Ajan teslim etmeden durduysa ya da teslimdeki taşıma sunucuda
                // başarısız olduysa kullanıcı elle taşır.
                if !link.state.isActive || link.state == .idle, entry.item.status != .inReview, entry.item.status != .done {
                    LumiActionButton(title: "Move to In Review") { store.moveToReview(entry.key) }
                }
                if link.state.isActive {
                    LumiActionButton(title: "Stop", kind: .destructive) { store.stopAgent(entry.key) }
                } else {
                    LumiActionButton(title: "Dismiss") { store.dismissAgent(entry.key) }
                }
            }
        }
    }
}
