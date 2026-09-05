import LumiKit
import LumiState
import SwiftUI

/// Agent History sekmesi (karar 39): Claude/Codex oturum geçmişi.
///
/// Satır düzeni Orca `AiVaultSessionRow`u izler: başlık + sağda aç/kapa oku
/// ve `⋯` menüsü; altında metadata ("Claude · 52 msgs · 3 subagents · 1h ago ·
/// model") ve branch rozeti; açıkken `AgentHistoryDetailCard`.
struct AgentHistoryView: View {
    let repoPath: String
    @Shell private var shell
    @State private var query = ""
    @State private var provider: AgentProvider?
    @State private var expanded: Set<String> = []
    @State private var newestFirst = true
    @State private var showsFilter = false
    @State private var menuEntryID: String?

    private var entries: [AgentHistoryEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = (shell.agentHistory.entries[repoPath] ?? []).filter {
            (provider == nil || $0.provider == provider)
                && (needle.isEmpty || $0.title.localizedCaseInsensitiveContains(needle)
                    || ($0.preview?.localizedCaseInsensitiveContains(needle) ?? false)
                    || $0.sessionID.localizedCaseInsensitiveContains(needle))
        }
        return newestFirst ? result : result.reversed()
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            searchField
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    status
                    ForEach(entries) { entry in sessionRow(entry) }
                }
            }
        }
        .task(id: repoPath) { await shell.agentHistory.refresh(repoPath) }
        .onChange(of: repoPath) { expanded = [] }
    }

    // MARK: - Üst şerit

    private var toolbar: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text((repoPath as NSString).lastPathComponent)
                .font(Theme.Typography.ui(.body, weight: .medium)).lineLimit(1)
            Spacer(minLength: 0)
            IconButton(systemName: "arrow.clockwise", label: "Refresh agent history") {
                Task { await shell.agentHistory.refresh(repoPath) }
            }
            .disabled(shell.agentHistory.loading.contains(repoPath))
            IconButton(
                systemName: "line.3.horizontal.decrease", label: "Filter and sort agent history",
                role: .toggle, isActive: provider != nil || !newestFirst
            ) { showsFilter.toggle() }
            .popover(isPresented: $showsFilter, arrowEdge: .bottom) {
                PopoverMenu(items: filterItems)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Spacing.xxxl)
    }

    private var filterItems: [PopoverMenu.Item] {
        [.section("Agent"), .toggle("All Agents", isOn: provider == nil) { provider = nil }]
            + AgentProvider.allCases.map { agent in
                .toggle(agent.rawValue.capitalized, isOn: provider == agent) { provider = agent }
            }
            + [.divider, .section("Order"), .toggle("Newest First", isOn: newestFirst) { newestFirst.toggle() }]
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.ui(.body))
                .foregroundStyle(Theme.textMuted)
                .accessibilityHidden(true)
            TextField("Search sessions…", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
                .font(Theme.Typography.ui(.body))
            if !query.isEmpty {
                IconButton(systemName: "xmark", label: "Clear search", size: .caption) { query = "" }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Spacing.xxxl - Theme.Spacing.xs)
        .background(Theme.bgDeep)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
        )
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
    }

    @ViewBuilder
    private var status: some View {
        if shell.agentHistory.loading.contains(repoPath) {
            ProgressView().controlSize(.small).padding(Theme.Spacing.lg)
        }
        if let error = shell.agentHistory.errors[repoPath] {
            Text(error).font(Theme.Typography.ui(.body)).foregroundStyle(Theme.error)
                .padding(Theme.Spacing.md)
        } else if entries.isEmpty && !shell.agentHistory.loading.contains(repoPath) {
            EmptyStatePlaceholder(
                query.isEmpty ? "No agent sessions for this project" : "No matching sessions",
                density: .inline
            )
        }
    }

    // MARK: - Satır

    private func sessionRow(_ entry: AgentHistoryEntry) -> some View {
        let isExpanded = expanded.contains(entry.id)
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Button { toggle(entry.id) } label: {
                    summary(entry, isExpanded: isExpanded).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(entry.title), \(isExpanded ? "collapse" : "expand")")
                rowActions(entry, isExpanded: isExpanded)
            }
            if isExpanded {
                AgentHistoryDetailCard(
                    entry: entry,
                    onResume: { resume(entry) },
                    onCopyCommand: { if let command = entry.resumeCommand { copy(command) } },
                    onRevealLog: { revealLog(entry) }
                )
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu { contextMenu(entry) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline) }
    }

    private func rowActions(_ entry: AgentHistoryEntry, isExpanded: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            IconButton(
                systemName: isExpanded ? "chevron.up" : "chevron.down",
                label: isExpanded ? "Collapse session" : "Expand session", size: .caption
            ) { toggle(entry.id) }
            IconButton(systemName: "ellipsis", label: "Session actions", size: .body) {
                menuEntryID = menuEntryID == entry.id ? nil : entry.id
            }
            .popover(
                isPresented: Binding(get: { menuEntryID == entry.id }, set: { if !$0 { menuEntryID = nil } }),
                arrowEdge: .bottom
            ) {
                PopoverMenu(items: menuItems(entry), dismiss: { menuEntryID = nil })
            }
        }
    }

    /// Başlık + (kapalıyken) önizleme + metadata + branch rozeti.
    private func summary(_ entry: AgentHistoryEntry, isExpanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(entry.title)
                .font(Theme.Typography.ui(.base, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(isExpanded ? 3 : 1)
                .fixedSize(horizontal: false, vertical: true)
            if let preview = entry.preview, !isExpanded {
                Text(preview).font(Theme.Typography.ui(.body))
                    .foregroundStyle(Theme.textSecondary).lineLimit(2)
            }
            metadata(entry)
            if let branch = entry.gitBranch { AgentHistoryBranchBadge(branch: branch) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "✳ Claude · 52 msgs · 3 subagents · 1h ago · opus-4-1".
    private func metadata(_ entry: AgentHistoryEntry) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            ProviderIcon(provider: entry.provider, size: .caption)
            Text(entry.provider.rawValue.capitalized)
            if entry.messageCount > 0 {
                separator
                Text("\(entry.messageCount) msgs").monospacedDigit()
            }
            if !entry.subagents.isEmpty {
                separator
                Text("\(entry.subagents.count) \(entry.subagents.count == 1 ? "subagent" : "subagents")")
            }
            separator
            Text(RelativeTimeFormatter.label(entry.updatedAt))
            if let model = entry.modelLabel {
                separator
                Text(model).lineLimit(1).truncationMode(.tail)
            }
        }
        .font(Theme.Typography.ui(.caption))
        .foregroundStyle(Theme.textMuted)
        .lineLimit(1)
    }

    private var separator: some View {
        Text("·").foregroundStyle(Theme.textMuted).accessibilityHidden(true)
    }

    // MARK: - Menüler ve eylemler

    private func menuItems(_ entry: AgentHistoryEntry) -> [PopoverMenu.Item] {
        [
            .action("Resume Session", icon: "play", isEnabled: entry.resumeCommand != nil) { resume(entry) },
            .action("Copy Resume Command", icon: "terminal", isEnabled: entry.resumeCommand != nil) {
                if let command = entry.resumeCommand { copy(command) }
            },
            .divider,
            .action("Copy Session ID", icon: "number") { copy(entry.sessionID) },
            .action("Copy Log Path", icon: "doc.on.doc") { copy(entry.logPath) },
            .action("Reveal Log in Finder", icon: "folder") { revealLog(entry) },
        ]
    }

    @ViewBuilder
    private func contextMenu(_ entry: AgentHistoryEntry) -> some View {
        Button("Resume Session") { resume(entry) }.disabled(entry.resumeCommand == nil)
        Button("Copy Session ID") { copy(entry.sessionID) }
        Button("Copy Log Path") { copy(entry.logPath) }
        Button("Copy Resume Command") { if let command = entry.resumeCommand { copy(command) } }
            .disabled(entry.resumeCommand == nil)
    }

    private func toggle(_ id: String) {
        expanded = expanded.contains(id) ? expanded.subtracting([id]) : expanded.union([id])
    }

    /// Log dosyasını Finder'da seçili açar (Orca'nın "View Log" eylemi).
    private func revealLog(_ entry: AgentHistoryEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.logPath)])
    }

    private func resume(_ entry: AgentHistoryEntry) {
        guard let command = entry.resumeCommand else { return }
        shell.terminals.spawn(in: repoPath, command: command)
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
