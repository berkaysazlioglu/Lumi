import LumiKit
import LumiState
import SwiftUI

/// Projects ▸ `Other` (karar 108): hiçbir projeye ait olmayan ("serbest")
/// terminaller, dizinlerine göre gruplanmış. Proje DEĞİLDİR — `+` yok, ⌃1–9
/// indekslemesine girmez, satır seçmek repo route'una değil All Terminals'a
/// gider (`ShellContext.focusAgent` → `NavigationStore.openTerminalSurface`).
/// Serbest terminal yokken hiç çizilmez.
struct OtherTerminalsSection: View {
    let searchText: String

    @Shell private var shell
    @State private var isCollapsed = false

    var body: some View {
        let groups = filteredGroups
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                header(count: groups.reduce(0) { $0 + $1.terminals.count })
                if !isCollapsed || !searchText.isEmpty {
                    ForEach(groups) { group in
                        LooseLocationRow(group: group)
                    }
                }
            }
            .padding(.bottom, Theme.Spacing.xs)
        }
    }

    private var filteredGroups: [LooseTerminalGroup] {
        let groups = shell.looseTerminalGroups
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return groups }
        return groups.filter { group in
            group.label.lowercased().contains(query)
                || group.terminals.contains { $0.displayTitle.lowercased().contains(query) }
        }
    }

    private func header(count: Int) -> some View {
        Button { isCollapsed.toggle() } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "tray")
                    .foregroundStyle(Theme.textMuted)
                    .accessibilityHidden(true)
                Text("Other")
                    .font(Theme.Typography.mono(.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(count)")
                    .font(Theme.Typography.captionMono)
                    .foregroundStyle(Theme.textMuted)
                Spacer(minLength: 0)
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(Theme.Typography.captionMono)
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: Theme.Spacing.xl, height: Theme.Spacing.xl)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Terminals opened outside any project")
        .accessibilityLabel(isCollapsed ? "Show terminals outside projects" : "Hide terminals outside projects")
    }
}

/// `Other` altındaki tek dizin: `~/Desktop` satırı + o dizindeki ajanlar.
private struct LooseLocationRow: View {
    let group: LooseTerminalGroup

    @Shell private var shell
    @State private var showsMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            ForEach(AgentRow.Model.sorted(group.terminals, terminals: shell.terminals), id: \.meta.id) { agent in
                AgentRow(agent: agent) { shell.focusAgent(agent.meta) }
            }
        }
        .padding(.vertical, Theme.Spacing.xxs)
    }

    private var row: some View {
        HoverReader { isHovering in
            Button { shell.navigation.setRoute(AllTerminalsRoute.route) } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "folder")
                        .foregroundStyle(Theme.textMuted)
                        .accessibilityHidden(true)
                    Text(group.label)
                        .font(Theme.Typography.labelMono)
                        .foregroundStyle(isHovering ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(.leading, Theme.Spacing.xl)
                .padding(.trailing, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show terminals in \(group.label)")
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .help(group.path)
        .onRightClick { showsMenu = true }
        .popover(isPresented: $showsMenu, arrowEdge: .bottom) {
            PopoverMenu(items: menuItems, dismiss: { showsMenu = false })
        }
    }

    private var menuItems: [PopoverMenu.Item] {
        let provider = shell.settings.current.aiProvider
        return [
            .action("New \(provider.displayName) Here", icon: "plus") {
                shell.looseTerminals.select(group.path)
                shell.navigation.setRoute(AllTerminalsRoute.route)
                shell.spawnTerminal(in: .all, command: provider.launchCommand)
            },
            .divider,
            .action("Reveal in Finder", icon: "folder") { shell.actions.revealPath(group.path) },
            .action("Copy Path", icon: "doc.on.doc") { Pasteboard.copy(group.path) },
        ]
    }
}
