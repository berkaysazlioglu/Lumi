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
        case .original: "main"
        case .workspace(let workspace): workspace.name
        }
    }

    var actionTitle: String {
        switch self {
        case .original(let repo): repo.name
        case .workspace(let workspace): workspace.name
        }
    }

    func identity(originalBranch: String? = nil) -> CheckoutIdentity {
        switch self {
        case .original:
            CheckoutIdentity(title: title, branch: originalBranch)
        case .workspace(let workspace):
            CheckoutIdentity(title: title, branch: workspace.branch)
        }
    }
}

struct CheckoutIdentity: Equatable {
    let title: String
    let branch: String?
}

/// Checkout satırı + ajan listesi (karar 51, Orca `WorktreeCard` sadeliği).
///
/// Satır: ikon · ad · (`primary` rozeti | branch) · sağda toplu durum.
/// Altında birden fazla ajan varsa "N agents" daraltıcısı, tek ajan doğrudan.
struct CheckoutRow: View {
    let checkout: Checkout
    @Shell private var shell
    @State private var isAgentListCollapsed = false
    @State private var showsMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            agentList
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(isActive ? Theme.textPrimary.opacity(0.10) : .clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .strokeBorder(isActive ? Theme.textSecondary.opacity(0.45) : .clear, lineWidth: Theme.Stroke.hairline)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Satır

    private var row: some View {
        HoverReader { isHovering in
            HStack(spacing: Theme.Spacing.sm) {
                Button { shell.navigation.openTab(checkout.path) } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        icon
                        Text(displayTitle)
                            .font(Theme.Typography.labelMono)
                            .foregroundStyle(isActive ? Theme.accentPrimary : Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        trailing
                        Spacer(minLength: 0)
                        summary
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isMissing)
                .accessibilityLabel("Open \(checkout.actionTitle)")
                // Karar 55: top bar tab şeridi kalktı; sekme kapatma satırın
                // kendisinde yaşar (yalnız açık bir sekmede, hover/aktifken).
                if isOpenTab {
                    closeTabButton
                        .opacity(isHovering || isActive ? 1 : 0)
                }
            }
            .padding(.leading, Theme.Spacing.xl)
            .padding(.trailing, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .help(checkout.path)
        // Proje satırıyla aynı: native `contextMenu` yerine Lumi `PopoverMenu`.
        .onRightClick { showsMenu = true }
        .popover(isPresented: $showsMenu, arrowEdge: .bottom) {
            PopoverMenu(items: menuItems, dismiss: { showsMenu = false })
        }
    }

    private var closeTabButton: some View {
        IconButton(
            systemName: "xmark",
            label: "Close \(checkout.actionTitle) tab",
            size: .micro,
            side: Theme.Spacing.xl,
            role: .destructive
        ) {
            shell.requestCloseTab(checkout.path, repoName: checkout.actionTitle)
        }
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
        if let branchLabel {
            Text(branchLabel)
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
            .map { meta in
                let isAwaitingDecision = shell.terminals.awaitingDecisionIDs.contains(meta.id)
                return AgentRow.Model(
                    meta: meta,
                    state: AgentActivityState(status: meta.status, isAwaitingDecision: isAwaitingDecision),
                    needsAttention: TerminalAttention.isNeeded(
                        status: meta.status,
                        isAwaitingDecision: isAwaitingDecision,
                        isSelected: shell.terminals.activeTerminalID == meta.id
                    )
                )
            }
            .sorted { lhs, rhs in
                lhs.state.sortRank != rhs.state.sortRank
                    ? lhs.state.sortRank < rhs.state.sortRank
                    : lhs.meta.lastActivityAt > rhs.meta.lastActivityAt
            }
    }

    // MARK: - Menü

    private var menuItems: [PopoverMenu.Item] {
        switch checkout {
        case .original(let repo):
            var items: [PopoverMenu.Item] = [
                .action("Create Workspace…", icon: "plus", isEnabled: !shell.workspaces.isCreating) {
                    shell.dialogs.present(.createWorkspace(projectPath: repo.path))
                },
            ]
            if isOpenTab {
                items.append(.action("Close Tab", icon: "xmark") { shell.requestCloseTab(repo.path, repoName: repo.name) })
            }
            items += [
                .action("Reveal in Finder", icon: "folder") { shell.actions.revealPath(repo.path) },
                .action("Copy Path", icon: "doc.on.doc") { Pasteboard.copy(repo.path) },
            ]
            return items
        case .workspace(let workspace):
            var items: [PopoverMenu.Item] = [
                .action("Open", icon: "arrow.up.forward.square", isEnabled: !isMissing) {
                    shell.navigation.openTab(workspace.path)
                },
            ]
            if isOpenTab {
                items.append(.action("Close Tab", icon: "xmark") {
                    shell.requestCloseTab(workspace.path, repoName: workspace.name)
                })
            }
            items += [
                .action("Reveal in Finder", icon: "folder", isEnabled: !isMissing) { shell.actions.revealPath(workspace.path) },
                .action("Copy Path", icon: "doc.on.doc") { Pasteboard.copy(workspace.path) },
                .divider,
                isMissing
                    ? .action("Remove from List", icon: "minus.circle") { Task { await shell.forgetWorkspace(workspace) } }
                    : .action(
                        "Delete Workspace…", icon: "trash", isDestructive: true,
                        isEnabled: !shell.workspaces.isDeleting
                    ) { shell.requestDeleteWorkspace(workspace) },
            ]
            return items
        }
    }

    // MARK: - Türevler

    private var displayTitle: String {
        identity.title
    }

    /// Original checkout da yönetilen workspace'lerle aynı iki kolonlu
    /// kimliği kullanır: solda sabit `main`, yanında gerçek SCM branch yolu.
    private var branchLabel: String? {
        identity.branch
    }

    private var identity: CheckoutIdentity {
        switch checkout {
        case .original(let repo):
            if let branch = shell.git.branches[repo.path]?.first(where: { $0.isCurrent }) {
                return checkout.identity(originalBranch: branch.name)
            }
            if let branch = shell.plastic.workspaces[repo.path]?.branch {
                return checkout.identity(originalBranch: PlasticBranchName.display(branch))
            }
            return checkout.identity()
        case .workspace:
            return checkout.identity()
        }
    }

    private var isActive: Bool { shell.navigation.activeRepoPath == checkout.path }

    /// Checkout açık bir sekme mi (kapatma yalnız o zaman anlamlı).
    private var isOpenTab: Bool { shell.navigation.openTabs.contains(checkout.path) }

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
        /// Karar 77: seçili değilken turn'ü kapanmış / karar bekleyen ajan.
        var needsAttention = false
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
                        .foregroundStyle(titleColor(isHovering: isHovering))
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
                .overlay(alignment: .leading) { attentionBar }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityLabel(
            agent.needsAttention
                ? "\(agent.state.title): \(agent.meta.displayTitle), needs attention"
                : "\(agent.state.title): \(agent.meta.displayTitle)"
        )
        .contextMenu {
            Button("Focus Session", action: onSelect)
            Button("Close Session", role: .destructive) { shell.terminals.close(agent.meta.id) }
        }
    }

    /// Karar 77 vurgusunun asıl gücü: ajan grubunun girinti hizasında duran
    /// dikey sarı çubuk. Zemini boyamak yerine boş bir kanal kullanır — satır
    /// zemini bu listede "seçili / hover" demektir.
    @ViewBuilder
    private var attentionBar: some View {
        if agent.needsAttention {
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(Theme.warning)
                // 2pt: ölçek dışı ara değer — hairline görünmüyor, 3pt bağırıyor.
                .frame(width: Theme.scaled(2))
                .padding(.vertical, Theme.Spacing.xxs)
                .padding(.leading, Theme.Spacing.xxl)
                .accessibilityHidden(true)
        }
    }

    /// Vurgu hover'ı EZER: sarı "ilgilenilmedi" bilgisidir, imleç oradan
    /// geçtiği için kaybolmamalı.
    private func titleColor(isHovering: Bool) -> Color {
        if agent.needsAttention { return Theme.warning }
        return isHovering ? Theme.textPrimary : Theme.textSecondary
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
