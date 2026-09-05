import LumiKit
import LumiState
import SwiftUI

struct SourceControlView: View {
    let repoPath: String
    @Shell private var shell
    @State private var showHistory = false
    @State private var refreshing = false

    private var changes: [GitFileChange] { shell.git.changes[repoPath] ?? [] }
    private var branch: GitBranch? { shell.git.branches[repoPath]?.first { $0.isCurrent } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "arrow.triangle.branch")
                Text(branch?.name ?? "No commits yet").lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                IconButton(systemName: "arrow.clockwise", label: "Refresh source control") {
                    let path = repoPath
                    refreshing = true
                    Task { await shell.git.refresh(path); refreshing = false }
                }
                .disabled(refreshing)
            }
            .font(Theme.Typography.ui(.body))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Spacing.xxxl)
            Picker("Source control view", selection: $showHistory) {
                Text("Changes (\(changes.count))").tag(false)
                Text("History").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .font(Theme.Typography.ui(.label))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.md)
            if showHistory {
                history
            } else {
                composer
                HStack {
                    Text("CHANGES").font(Theme.Typography.ui(.label, weight: .semibold))
                    Spacer()
                    Button(selectedCount == changes.count ? "Deselect All" : "Select All") {
                        shell.git.toggleSelectAll(repoPath)
                    }
                    .buttonStyle(.plain)
                    .font(Theme.Typography.ui(.caption))
                    .disabled(changes.isEmpty)
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(Theme.Spacing.md)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if changes.isEmpty {
                            EmptyStatePlaceholder("No changes — working tree clean", density: .inline)
                        }
                        ForEach(changes) { change in changeRow(change) }
                    }
                }
            }
        }
        .onChange(of: repoPath) { showHistory = false }
    }

    private var selectedCount: Int { shell.git.selectedFiles[repoPath]?.count ?? 0 }

    private var composer: some View {
        VStack(spacing: Theme.Spacing.md) {
            TextField("Commit message…", text: Binding(
                get: { shell.git.commitMessage(for: repoPath) },
                set: { shell.git.setCommitMessage($0, for: repoPath) }
            ), axis: .vertical)
            .lineLimit(2...5)
            .font(Theme.Typography.ui(.body))
            .textFieldStyle(.plain)
            .foregroundStyle(Theme.textPrimary)
            .padding(Theme.Spacing.md)
            .background(Theme.bgDeep)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            Button {
                Task { await shell.git.commit(repoPath) }
            } label: {
                Label(shell.git.isCommitting ? "Committing…" : "Commit (\(selectedCount))", systemImage: "checkmark")
                    .font(Theme.Typography.ui(.body, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .foregroundStyle(.white)
                    .background(Theme.accentVivid)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(!shell.git.canCommit(repoPath))
            .opacity(shell.git.canCommit(repoPath) ? 1 : 0.4)
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    private func changeRow(_ change: GitFileChange) -> some View {
        let color = Theme.fileChangeColor(for: change.status)
        return HStack(spacing: Theme.Spacing.sm) {
            Button { shell.git.toggleFile(repoPath, path: change.path) } label: {
                Image(systemName: shell.git.isSelected(repoPath, path: change.path) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Include \(change.path) in commit")
            .accessibilityLabel("Include \(change.path) in commit")
            Button { shell.presentDiff(change.path) } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "doc")
                    Text((change.path as NSString).lastPathComponent).lineLimit(1)
                    Text((change.path as NSString).deletingLastPathComponent)
                        .foregroundStyle(Theme.textMuted).lineLimit(1).truncationMode(.head)
                    Spacer(minLength: 0)
                    Text(change.status.badgeText)
                }
                .foregroundStyle(color)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(change.path)
            .contextMenu {
                Button("Open Changes") { shell.presentDiff(change.path) }
                if change.status != .deleted { Button("Open File") { shell.presentFile(change.path) } }
                Button("Reveal in Finder") { shell.reveal(change.path) }
            }
        }
        .font(Theme.Typography.ui(.body))
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var history: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let commits = branch.flatMap { shell.git.commitsByBranch[repoPath]?[$0.name] } ?? []
                if commits.isEmpty { EmptyStatePlaceholder("No commits", density: .inline) }
                ForEach(commits) { commit in
                    Button { shell.presentCommit(commit) } label: {
                        HStack(alignment: .top, spacing: Theme.Spacing.md) {
                            Image(systemName: "circle.inset.filled")
                                .foregroundStyle(Theme.accentPrimary)
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text(commit.message).lineLimit(2).foregroundStyle(Theme.textPrimary)
                                Text("\(commit.shortHash) · \(commit.author)")
                                    .foregroundStyle(Theme.textSecondary)
                                Text(commit.date, style: .relative).foregroundStyle(Theme.textMuted)
                            }
                            Spacer(minLength: 0)
                        }
                        .font(Theme.Typography.ui(.body))
                        .padding(Theme.Spacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
