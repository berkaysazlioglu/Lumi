import LumiKit
import LumiState
import SwiftUI

/// Resource Manager popover'ı (Orca `ResourceUsagePopoverContent`).
///
/// Başlık (ad + Refresh + Kill all) → özet (CPU · Σ RSS) → kolon başlığı →
/// sabit yükseklikli liste (repo grupları / oturumlar + LUMI bölümü).
/// Kill eylemleri önce satır içi onay kartı gösterir (native dialog yok).
struct ResourceManagerPopover: View {
    enum PendingKill: Equatable {
        case session(ResourceUsageStore.SessionRow)
        case all
    }

    @Shell private var shell
    @State private var pending: PendingKill?

    private var store: ResourceUsageStore { shell.resourceUsage }

    var body: some View {
        VStack(spacing: 0) {
            header
            summary
            if let pending {
                confirm(pending)
            } else {
                list
            }
        }
        .frame(width: StatusBarMetrics.popoverWidth)
        .background(Theme.bgElevated)
    }

    // MARK: - Üst bölüm

    private var header: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "memorychip")
                .font(Theme.Typography.ui(.label))
                .foregroundStyle(Theme.textMuted)
                .accessibilityHidden(true)
            Text("Resource Manager")
                .font(Theme.Typography.ui(.label, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            IconButton(systemName: "arrow.clockwise", label: "Refresh resource usage", size: .caption, weight: .semibold) {
                Task { await store.refresh() }
            }
            .disabled(store.isSampling)
            IconButton(systemName: "trash", label: "Kill all sessions", size: .caption, weight: .semibold, role: .destructive) {
                pending = .all
            }
            .disabled(store.sessionCount == 0)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: Theme.Row.control + Theme.Spacing.xs)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline) }
    }

    @ViewBuilder
    private var summary: some View {
        if store.snapshot != nil {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.lg) {
                Text(ResourceUsageFormat.cpu(store.terminalCPUPercent))
                    .help("Combined CPU load. Values above 100% mean more than one core is working at once.")
                Text("·").foregroundStyle(Theme.textMuted.opacity(Self.separatorOpacity)).accessibilityHidden(true)
                HStack(spacing: Theme.Spacing.xs) {
                    Text(ResourceUsageFormat.memory(store.terminalMemoryBytes))
                    Text("Σ RSS").font(Theme.Typography.ui(.body)).foregroundStyle(Theme.textMuted)
                }
                .help("Summed resident set size (RSS). Shared or aliased pages can appear in more than one process.")
                Spacer(minLength: 0)
            }
            .font(Theme.Typography.ui(.body, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline) }
        }
    }

    // MARK: - Liste

    private var list: some View {
        VStack(spacing: 0) {
            ResourceColumnHeader(sort: Binding(get: { store.sortOption }, set: { store.sortOption = $0 }))
            ScrollView {
                LazyVStack(spacing: 0) {
                    tree
                    if let snapshot = store.snapshot {
                        ResourceAppSection(
                            app: snapshot.app,
                            history: store.appMemoryHistory,
                            isCollapsed: store.isAppCollapsed,
                            onToggle: { store.isAppCollapsed.toggle() }
                        )
                    } else {
                        EmptyStatePlaceholder("Loading…", density: .inline)
                    }
                }
            }
        }
        .frame(height: StatusBarMetrics.popoverBodyHeight)
    }

    /// Tek repo → oturumlar düz listelenir (Orca `sortedRepos.length === 1`).
    @ViewBuilder
    private var tree: some View {
        let groups = store.repoGroups
        if groups.isEmpty {
            if store.snapshot != nil {
                EmptyStatePlaceholder("Nothing running right now", density: .inline)
            }
        } else if groups.count == 1, let only = groups.first {
            ForEach(only.sessions) { sessionRow($0) }
        } else {
            ForEach(groups) { group in
                let isCollapsed = store.collapsedRepos.contains(group.id)
                ResourceRepoGroupRow(group: group, isCollapsed: isCollapsed) { store.toggleRepo(group.id) }
                if !isCollapsed {
                    ForEach(group.sessions) { sessionRow($0) }
                }
                Rectangle().fill(Theme.border.opacity(Self.groupDividerOpacity)).frame(height: Theme.Stroke.hairline)
            }
        }
    }

    private func sessionRow(_ session: ResourceUsageStore.SessionRow) -> some View {
        ResourceSessionRow(
            session: session,
            onNavigate: { navigate(to: session.id) },
            onKill: { pending = .session(session) }
        )
    }

    /// Oturumun repo'suna geçip terminali odaklar (minimize ise geri alır).
    private func navigate(to id: TerminalID) {
        guard let meta = shell.terminals.meta(for: id) else { return }
        shell.navigation.openTab(meta.repoPath)
        shell.terminals.restoreAndFocus(id)
    }

    // MARK: - Onay kartı

    private func confirm(_ pending: PendingKill) -> some View {
        let title: String
        let detail: String
        switch pending {
        case .session(let row):
            title = "Kill \(row.title)?"
            detail = "Force-quits this terminal. Any unsaved work in the pane is lost. This can't be undone."
        case .all:
            title = "Kill all \(store.sessionCount) sessions?"
            detail = "Force-quits every terminal in every repo. Unsaved work is lost. This can't be undone."
        }
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(title)
                .font(Theme.Typography.ui(.base, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(detail)
                .font(Theme.Typography.ui(.body))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Spacing.sm) {
                Spacer(minLength: 0)
                confirmButton("Cancel", isDestructive: false) { self.pending = nil }
                confirmButton("Kill", isDestructive: true) {
                    switch pending {
                    case .session(let row): store.kill(row.id)
                    case .all: store.killAll()
                    }
                    self.pending = nil
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(height: StatusBarMetrics.popoverBodyHeight, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func confirmButton(_ title: String, isDestructive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.ui(.body, weight: .medium))
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(height: Theme.Row.control)
        }
        .buttonStyle(
            HoverButtonStyle(
                foreground: isDestructive ? .white : Theme.textPrimary,
                hoverForeground: .white,
                background: isDestructive ? Theme.error : Theme.bgDeep,
                hoverBackground: isDestructive ? Theme.error.opacity(Self.destructiveHoverOpacity) : Theme.border
            )
        )
    }

    private static let separatorOpacity = 0.5
    private static let groupDividerOpacity = 0.5
    private static let destructiveHoverOpacity = 0.85
}

#if DEBUG
#Preview("ResourceManagerPopover") {
    ResourceManagerPopover()
        .environment(\.shell, ShellContext.preview())
}
#endif
