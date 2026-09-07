import LumiKit
import LumiState
import SwiftUI

/// Projects panelindeki bir checkout: projenin kendisi (`primary`) ya da
/// yönetilen bir workspace. Altında o yoldaki canlı ajanlar listelenir.
enum Checkout: Identifiable {
    case original(Repo)
    case workspace(ProjectWorkspace)

    var id: String { path }

    var path: String {
        switch self {
        case .original(let repo): repo.path
        case .workspace(let workspace): workspace.path
        }
    }

    var title: String {
        switch self {
        case .original(let repo): repo.name
        case .workspace(let workspace): workspace.name
        }
    }
}

/// Checkout satırı + ajan listesi (karar 49, Orca `WorktreeCard` sadeliği).
///
/// Satır: ikon · ad · (`primary` rozeti | branch) · sağda toplu durum.
/// Altında birden fazla ajan varsa "N agents" daraltıcısı, tek ajan doğrudan.
struct CheckoutRow: View {
    let checkout: Checkout
    @Shell private var shell
    @State private var isAgentListCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            agentList
        }
    }

    // MARK: - Satır

    private var row: some View {
        Button { shell.navigation.openTab(checkout.path) } label: {
            HStack(spacing: Theme.Spacing.sm) {
                icon
                Text(checkout.title)
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(isActive ? Theme.accentPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                trailing
                Spacer(minLength: 0)
                summary
            }
            .padding(.leading, Theme.Spacing.xl)
            .padding(.trailing, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isActive ? Theme.bgElevated : .clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .disabled(isMissing)
        .help(checkout.path)
        .accessibilityLabel("Open \(checkout.title)")
        .contextMenu { contextMenu }
    }

    @ViewBuilder
    private var icon: some View {
        switch checkout {
        case .original:
            Image(systemName: "house").foregroundStyle(Theme.textMuted).accessibilityHidden(true)
        case .workspace:
            Image(systemName: "arrow.triangle.branch").foregroundStyle(Theme.textMuted).accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch checkout {
        case .original:
            Badge(text: "primary", style: .neutral)
        case .workspace(let workspace):
            Text(workspace.branch)
                .font(Theme.Typography.captionMono)
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// Sağ uç: eksik uyarısı ya da (liste daraltıldığında) toplu durum + sayı.
    @ViewBuilder
    private var summary: some View {
        if isMissing {
            Text("Missing").font(Theme.Typography.captionMono).foregroundStyle(Theme.warning)
        } else if isAgentListCollapsed, let lead = agents.first {
            HStack(spacing: Theme.Spacing.xs) {
                AgentActivityIcon(state: lead.state, size: .caption)
                Text("\(agents.count)").font(Theme.Typography.captionMono).foregroundStyle(Theme.textMuted)
            }
        }
    }

    // MARK: - Ajanlar

    @ViewBuilder
    private var agentList: some View {
        if agents.count > 1 {
            agentSummaryToggle
        }
        if !isAgentListCollapsed || agents.count == 1 {
            ForEach(agents, id: \.meta.id) { agent in
                AgentRow(agent: agent) { shell.focusAgent(agent.meta) }
            }
        }
    }

    private var agentSummaryToggle: some View {
        Button { isAgentListCollapsed.toggle() } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Text("\(agents.count) agents")
                    .font(Theme.Typography.captionMono)
                    .foregroundStyle(Theme.textMuted)
                Spacer(minLength: 0)
                Image(systemName: isAgentListCollapsed ? "chevron.right" : "chevron.down")
                    .font(Theme.Typography.captionMono)
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.leading, Theme.Spacing.xxl + Theme.Spacing.md)
            .padding(.trailing, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isAgentListCollapsed ? "Show agents" : "Hide agents")
    }

    /// Dikkat isteyenler önce, sonra çalışanlar, sonra bitenler; eşitlikte en
    /// yeni etkinlik üstte (Orca `smart` sıralaması).
    private var agents: [AgentRow.Model] {
        shell.terminals.terminals(in: checkout.path)
            .map { AgentRow.Model(meta: $0, state: AgentActivityState(
                status: $0.status, isAwaitingDecision: shell.terminals.awaitingDecisionIDs.contains($0.id)
            )) }
            .sorted { lhs, rhs in
                lhs.state.sortRank != rhs.state.sortRank
                    ? lhs.state.sortRank < rhs.state.sortRank
                    : lhs.meta.lastActivityAt > rhs.meta.lastActivityAt
            }
    }

    // MARK: - Menü

    @ViewBuilder
    private var contextMenu: some View {
        switch checkout {
        case .original(let repo):
            Button("Create Workspace…") { shell.dialogs.present(.createWorkspace(projectPath: repo.path)) }
                .disabled(shell.workspaces.isCreating)
            Button("Reveal in Finder") { shell.actions.revealPath(repo.path) }
            Button("Copy Path") { Pasteboard.copy(repo.path) }
        case .workspace(let workspace):
            Button("Open") { shell.navigation.openTab(workspace.path) }.disabled(isMissing)
            Button("Reveal in Finder") { shell.actions.revealPath(workspace.path) }.disabled(isMissing)
            Button("Copy Path") { Pasteboard.copy(workspace.path) }
            Divider()
            if isMissing {
                Button("Remove from List") { Task { await shell.forgetWorkspace(workspace) } }
            } else {
                Button("Delete Workspace…", role: .destructive) { shell.requestDeleteWorkspace(workspace) }
                    .disabled(shell.workspaces.isDeleting)
            }
        }
    }

    // MARK: - Türevler

    private var isActive: Bool { shell.navigation.activeRepoPath == checkout.path }

    private var isMissing: Bool {
        if case .workspace(let workspace) = checkout { return shell.workspaces.isMissing(workspace) }
        return false
    }
}

/// Tek ajan satırı: durum glifi · kimlik ikonu · başlık · kısa zaman.
struct AgentRow: View {
    struct Model {
        let meta: TerminalMeta
        let state: AgentActivityState
    }

    let agent: Model
    let onSelect: () -> Void
    @Shell private var shell

    var body: some View {
        HoverReader { isHovering in
            Button(action: onSelect) {
                HStack(spacing: Theme.Spacing.sm) {
                    AgentActivityIcon(state: agent.state, size: .caption)
                    TerminalIdentityIcon(provider: agent.meta.provider, size: .caption)
                    Text(agent.meta.displayTitle)
                        .font(Theme.Typography.captionMono)
                        .foregroundStyle(isHovering ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Text(RelativeTimeFormatter.shortLabel(agent.meta.lastActivityAt))
                        .font(Theme.Typography.captionMono)
                        .foregroundStyle(Theme.textMuted)
                        .monospacedDigit()
                }
                .padding(.leading, Theme.Spacing.xxl + Theme.Spacing.md)
                .padding(.trailing, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(isHovering ? Theme.bgElevated : .clear)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityLabel("\(agent.state.title): \(agent.meta.displayTitle)")
        .contextMenu {
            Button("Focus Session", action: onSelect)
            Button("Close Session", role: .destructive) { shell.terminals.close(agent.meta.id) }
        }
    }
}

#if DEBUG
#Preview("CheckoutRow") {
    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
        CheckoutRow(checkout: .original(Repo(name: "Lumi", path: "/Users/preview/Projects/lumi", isGitRepo: true, source: .standalone)))
        CheckoutRow(checkout: .workspace(ProjectWorkspace(
            projectPath: "/Users/preview/Projects/lumi", path: "/Users/preview/lumi/workspaces/lumi/review",
            name: "review", branch: "feat/review", scm: .git
        )))
    }
    .padding(Theme.Spacing.lg)
    .frame(width: 300)
    .background(Theme.bgSurface)
    .environment(\.shell, ShellContext.preview())
}
#endif
