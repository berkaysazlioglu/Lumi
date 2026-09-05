import LumiKit
import LumiState
import SwiftUI

struct AgentHistoryView: View {
    let repoPath: String
    @Shell private var shell
    @State private var query = ""
    @State private var provider: AgentProvider?
    @State private var expanded: Set<String> = []
    @State private var newestFirst = true

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
            HStack(spacing: Theme.Spacing.sm) {
                Text((repoPath as NSString).lastPathComponent)
                    .font(Theme.Typography.ui(.body, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                IconButton(systemName: "arrow.clockwise", label: "Refresh agent history") {
                    Task { await shell.agentHistory.refresh(repoPath) }
                }
                .disabled(shell.agentHistory.loading.contains(repoPath))
                Menu {
                    Button("All Agents") { provider = nil }
                    ForEach(AgentProvider.allCases, id: \.self) { agent in
                        Button(agent.rawValue.capitalized) { provider = agent }
                    }
                    Divider()
                    Toggle("Newest First", isOn: $newestFirst)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(Theme.Typography.ui(.body))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Filter and sort agent history")
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Spacing.xxxl)
            TextField("Search sessions…", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
                .font(Theme.Typography.ui(.body))
                .padding(Theme.Spacing.md)
                .background(Theme.bgDeep)
            if let provider {
                Text(provider.rawValue.capitalized)
                    .font(Theme.Typography.ui(.caption)).foregroundStyle(Theme.accentPrimary)
                    .padding(Theme.Spacing.xs)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if shell.agentHistory.loading.contains(repoPath) {
                        ProgressView().controlSize(.small).padding(Theme.Spacing.lg)
                    }
                    if let error = shell.agentHistory.errors[repoPath] {
                        Text(error).font(Theme.Typography.ui(.body)).foregroundStyle(Theme.error)
                            .padding(Theme.Spacing.md)
                    } else if entries.isEmpty && !shell.agentHistory.loading.contains(repoPath) {
                        EmptyStatePlaceholder(query.isEmpty ? "No agent sessions for this project" : "No matching sessions", density: .inline)
                    }
                    ForEach(entries) { entry in sessionRow(entry) }
                }
            }
        }
        .task(id: repoPath) { await shell.agentHistory.refresh(repoPath) }
        .onChange(of: repoPath) { expanded = [] }
    }

    private func sessionRow(_ entry: AgentHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Button {
                if !expanded.insert(entry.id).inserted { expanded.remove(entry.id) }
            } label: {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    ProviderIcon(provider: entry.provider)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(entry.title).foregroundStyle(Theme.textPrimary)
                            .font(Theme.Typography.ui(.body, weight: .medium)).lineLimit(2)
                        if let preview = entry.preview {
                            Text(preview).font(Theme.Typography.ui(.body))
                                .foregroundStyle(Theme.textSecondary).lineLimit(2)
                        }
                        Text(entry.updatedAt, style: .relative)
                            .font(Theme.Typography.ui(.caption)).foregroundStyle(Theme.textMuted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: expanded.contains(entry.id) ? "chevron.down" : "chevron.right")
                        .font(Theme.Typography.ui(.caption)).foregroundStyle(Theme.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded.contains(entry.id) {
                Text(entry.sessionID).textSelection(.enabled)
                    .font(Theme.Typography.mono(.caption)).foregroundStyle(Theme.textSecondary)
                if let preview = entry.preview {
                    Text(preview).font(Theme.Typography.ui(.body)).textSelection(.enabled)
                }
                Button("Resume Session") { resume(entry) }
                    .disabled(entry.resumeCommand == nil)
                    .font(Theme.Typography.ui(.body, weight: .medium))
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Resume Session") { resume(entry) }.disabled(entry.resumeCommand == nil)
            Button("Copy Session ID") { copy(entry.sessionID) }
            Button("Copy Log Path") { copy(entry.logPath) }
            Button("Copy Resume Command") { if let command = entry.resumeCommand { copy(command) } }
                .disabled(entry.resumeCommand == nil)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline) }
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
