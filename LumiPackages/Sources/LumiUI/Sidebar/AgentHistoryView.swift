import LumiKit
import LumiState
import SwiftUI

/// Agent History sekmesi (karar 39): Claude/Codex oturum geçmişi.
///
/// Satır düzeni Orca `AiVaultSessionRow`u izler: başlık + sağda (hover'da)
/// Resume / Copy Command, aç/kapa oku ve `⋯` menüsü (sağ tık da aynı
/// `PopoverMenu`yu açar, karar 53); altında son turun rol etiketli önizlemesi
/// ve metadata ("Claude · 52 msgs · 3 subagents · 1h ago · model"); açıkken
/// `AgentHistoryDetailCard`.
struct AgentHistoryView: View {
    let repoPath: String
    @Shell private var shell
    @State private var query = ""
    @State private var provider: AgentProvider?
    @State private var expanded: Set<String> = []
    @State private var newestFirst = true
    @State private var showsFilter = false
    @State private var menuEntryID: String?
    @State private var hoveredEntryID: String?
    @State private var showsImportMenu = false

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
            IconButton(systemName: "square.and.arrow.down", label: "Import session") {
                showsImportMenu.toggle()
            }
            .disabled(shell.agentHistory.isTransferring)
            .popover(isPresented: $showsImportMenu, arrowEdge: .bottom) {
                PopoverMenu(items: importItems, dismiss: { showsImportMenu = false })
            }
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

    /// Karar 138: dosyadan (karar 52) ya da oturum sunucusundan.
    private var importItems: [PopoverMenu.Item] {
        var items: [PopoverMenu.Item] = [
            .action("Import from File…", icon: "doc") {
                showsImportMenu = false
                importSession()
            },
        ]
        if let sessionShare = shell.sessionShare {
            items.append(.action("Import from Server…", icon: "server.rack") {
                showsImportMenu = false
                sessionShare.openBrowser()
            })
        }
        return items
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

    /// Orca `AiVaultSessionRow` düzeni: üstte başlık + eylemler (Resume ve Copy
    /// Command yalnız hover'da belirir), altında tam genişlikte son turun
    /// rol etiketli önizlemesi ve metadata; açıkken `AgentHistoryDetailCard`.
    private func sessionRow(_ entry: AgentHistoryEntry) -> some View {
        let isExpanded = expanded.contains(entry.id)
        let isHovered = hoveredEntryID == entry.id
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(alignment: .center, spacing: Theme.Spacing.xs) {
                    title(entry, isExpanded: isExpanded)
                    rowActions(entry, isExpanded: isExpanded, showsHoverActions: isHovered || menuEntryID == entry.id)
                }
                if !isExpanded { preview(entry) }
                metadata(entry)
            }
            .contentShape(Rectangle())
            .onTapGesture { toggle(entry.id) }
            if isExpanded {
                AgentHistoryDetailCard(
                    entry: entry,
                    onResume: { resume(entry) },
                    onCopyCommand: { if let command = entry.resumeCommand { copy(command) } },
                    onRevealLog: { revealLog(entry) },
                    onExport: { exportSession(entry) }
                )
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered && !isExpanded ? Theme.bgElevated.opacity(Self.hoverTint) : Color.clear)
        .onHover { inside in
            if inside {
                hoveredEntryID = entry.id
            } else if hoveredEntryID == entry.id {
                hoveredEntryID = nil
            }
        }
        .onRightClick { menuEntryID = entry.id }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline) }
    }

    private static let hoverTint = 0.55

    private func title(_ entry: AgentHistoryEntry, isExpanded: Bool) -> some View {
        Text(entry.title)
            .font(Theme.Typography.ui(.base, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(isExpanded ? 2 : 1)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(entry.title)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(entry.title), \(isExpanded ? "collapse" : "expand")")
            .accessibilityAction { toggle(entry.id) }
    }

    private func rowActions(_ entry: AgentHistoryEntry, isExpanded: Bool, showsHoverActions: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            if showsHoverActions {
                IconButton(systemName: "play", label: "Resume session", size: .body, weight: .medium) {
                    resume(entry)
                }
                .disabled(entry.resumeCommand == nil)
                IconButton(systemName: "terminal", label: "Copy resume command", size: .body, weight: .medium) {
                    if let command = entry.resumeCommand { copy(command) }
                }
                .disabled(entry.resumeCommand == nil)
            }
            IconButton(
                systemName: isExpanded ? "chevron.up" : "chevron.down",
                label: isExpanded ? "Hide details" : "Show details", size: .body, weight: .medium
            ) { toggle(entry.id) }
            IconButton(systemName: "ellipsis", label: "Session actions", size: .body, weight: .medium) {
                menuEntryID = menuEntryID == entry.id ? nil : entry.id
            }
            .popover(
                isPresented: Binding(get: { menuEntryID == entry.id }, set: { if !$0 { menuEntryID = nil } }),
                arrowEdge: .bottom
            ) {
                PopoverMenu(items: menuItems(entry), dismiss: { menuEntryID = nil })
            }
        }
        .fixedSize()
    }

    /// "**Agent**: son tur metni" — iki satır, satır sonları boşluğa iner.
    /// Tur yoksa eski tek metin önizlemesi, o da yoksa yer tutucu.
    private func preview(_ entry: AgentHistoryEntry) -> some View {
        let latest = entry.recentTurns.last
        let body = (latest?.text ?? entry.preview)?
            .split(whereSeparator: \.isNewline).joined(separator: " ")
        let text: Text
        if let body, !body.isEmpty {
            let role = latest.map { $0.role == .user ? "You" : "Agent" }
            text = role.map {
                Text($0).fontWeight(.semibold).foregroundColor(Theme.textPrimary.opacity(Self.roleOpacity))
                    + Text(": \(body)")
            } ?? Text(body)
        } else {
            text = Text("No conversation preview available")
        }
        return text
            .font(Theme.Typography.ui(.body))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let roleOpacity = 0.85

    /// "✳ Claude · 52 msgs · 3 subagents · 1h ago · opus-4-1" — sabit öğeler
    /// kısalmaz, sığmazsa önce model, sonra sağlayıcı adı kırpılır.
    private func metadata(_ entry: AgentHistoryEntry) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            ProviderIcon(provider: entry.provider, size: .label)
            Text(entry.provider.rawValue.capitalized).lineLimit(1).layoutPriority(-1)
            if entry.messageCount > 0 {
                separator
                Text("\(entry.messageCount) msgs").monospacedDigit().fixedSize()
            }
            if !entry.subagents.isEmpty {
                separator
                Text("\(entry.subagents.count) \(entry.subagents.count == 1 ? "subagent" : "subagents")")
                    .fixedSize()
            }
            separator
            Text(RelativeTimeFormatter.label(entry.updatedAt)).fixedSize()
            if let model = entry.modelLabel {
                separator
                Text(model).lineLimit(1).truncationMode(.tail).layoutPriority(-2).help(model)
            }
        }
        .font(Theme.Typography.ui(.label))
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var separator: some View {
        Text("·").foregroundStyle(Theme.textMuted).fixedSize().accessibilityHidden(true)
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
            .divider,
            .action("Export as File…", icon: "square.and.arrow.up", isEnabled: !shell.agentHistory.isTransferring) {
                exportSession(entry)
            },
            .action("Export to Server…", icon: "icloud.and.arrow.up", isEnabled: canExportToServer) {
                exportToServer(entry)
            },
            .divider,
            .action("Delete Session…", icon: "trash", isDestructive: true, isEnabled: !shell.agentHistory.isTransferring) {
                shell.requestDeleteAgentSession(entry, projectPath: repoPath)
            },
        ]
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

    /// Karar 52: paket dosyası seçilir, yazım store/servis'te; sonuç toast'la gelir.
    private func exportSession(_ entry: AgentHistoryEntry) {
        menuEntryID = nil
        guard let destination = AgentSessionFilePanels.chooseExportDestination(for: entry) else { return }
        Task { await shell.agentHistory.exportSession(entry, to: destination) }
    }

    private var canExportToServer: Bool {
        shell.sessionShare != nil && !shell.agentHistory.isTransferring && shell.sessionShare?.exportDraft == nil
    }

    /// Karar 138: onay penceresi; varsayılan proje adı Lumi'deki projenin adı.
    private func exportToServer(_ entry: AgentHistoryEntry) {
        menuEntryID = nil
        let projectPath = shell.navigation.projectPath(containing: repoPath) ?? repoPath
        let name = shell.repos.repo(at: projectPath)?.name ?? (projectPath as NSString).lastPathComponent
        shell.sessionShare?.beginExport(entry, projectName: name)
    }

    private func importSession() {
        guard let source = AgentSessionFilePanels.chooseImportSource() else { return }
        Task { await shell.agentHistory.importSession(from: source, projectPath: repoPath) }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
