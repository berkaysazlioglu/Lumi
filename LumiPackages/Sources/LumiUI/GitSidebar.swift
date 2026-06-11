import LumiKit
import LumiState
import SwiftUI

/// Sağ sidebar: Commits (branch accordion) + Changes (status + commit akışı)
/// (spec/12 §2-5 UI davranışları, spec/21 §16).
struct GitSidebar: View {
    let repoPath: String
    let gitStore: GitStore
    let onSelectCommit: (GitCommit) -> Void
    let onShowFileDiff: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    commitsSection
                    Rectangle()
                        .fill(Theme.border)
                        .frame(height: 1)
                        .padding(.vertical, 8)
                    changesSection
                }
                .padding(.vertical, 8)
            }
            commitComposer
        }
        .background(Theme.bgSurface)
    }

    // MARK: - Commits (branch accordion)

    private var commitsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionTitle("COMMITS")
            ForEach(gitStore.branches[repoPath] ?? []) { branch in
                branchRow(branch)
                if gitStore.isBranchExpanded(repoPath, name: branch.name) {
                    commitList(for: branch)
                }
            }
            if (gitStore.branches[repoPath] ?? []).isEmpty {
                Text("(git reposu değil)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 12)
            }
        }
    }

    private func branchRow(_ branch: GitBranch) -> some View {
        Button {
            gitStore.toggleBranch(repoPath, name: branch.name)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: gitStore.isBranchExpanded(repoPath, name: branch.name)
                    ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                    .foregroundStyle(branch.isCurrent ? Theme.accentPrimary : Theme.textMuted)
                Text(branch.name)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(branch.isCurrent ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                if branch.isCurrent {
                    Text("current")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.accentPrimary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.accentPrimary.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func commitList(for branch: GitBranch) -> some View {
        let commits = gitStore.commitsByBranch[repoPath]?[branch.name] ?? []
        return VStack(alignment: .leading, spacing: 1) {
            if commits.isEmpty {
                Text("(branch'e özgü commit yok)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.leading, 28)
                    .padding(.vertical, 2)
            }
            ForEach(commits) { commit in
                Button {
                    onSelectCommit(commit)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(commit.message)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Text(commit.shortHash)
                                .foregroundStyle(Theme.accentCyan)
                            Text(commit.author)
                                .foregroundStyle(Theme.textMuted)
                            Text(Self.relativeTime(commit.date))
                                .foregroundStyle(Theme.textMuted)
                        }
                        .font(.system(size: 10, design: .monospaced))
                    }
                    .padding(.leading, 28)
                    .padding(.trailing, 8)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// "5m ago / 3h ago / 2d ago" — relative format UI katmanında (spec/12 §2).
    static func relativeTime(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    // MARK: - Changes

    private var changesSection: some View {
        let changes = gitStore.changes[repoPath] ?? []
        let selectedCount = gitStore.selectedFiles[repoPath]?.count ?? 0
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                sectionTitle("CHANGES (\(changes.count))")
                Spacer()
                if !changes.isEmpty {
                    Button(selectedCount == changes.count ? "Deselect All" : "Select All") {
                        gitStore.toggleSelectAll(repoPath)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.accentPrimary)
                    .padding(.trailing, 10)
                }
            }
            if changes.isEmpty {
                Text("(değişiklik yok)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 12)
            }
            ForEach(changes) { change in
                changeRow(change)
            }
        }
    }

    private func changeRow(_ change: GitFileChange) -> some View {
        HStack(spacing: 6) {
            Button {
                gitStore.toggleFile(repoPath, path: change.path)
            } label: {
                Image(systemName: gitStore.isSelected(repoPath, path: change.path)
                    ? "checkmark.square.fill" : "square")
                    .font(.system(size: 11))
                    .foregroundStyle(gitStore.isSelected(repoPath, path: change.path)
                        ? Theme.accentVivid : Theme.textMuted)
            }
            .buttonStyle(.plain)

            Text(change.status.badge)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.fileChangeColor(for: change.status))
                .frame(width: 12)

            Text((change.path as NSString).lastPathComponent)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .help(change.path)

            Spacer()

            Button {
                onShowFileDiff(change.path)
            } label: {
                Image(systemName: "plus.forwardslash.minus")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
            }
            .buttonStyle(.plain)
            .help("Show diff")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2.5)
    }

    // MARK: - Commit composer (spec/12 §5)

    private var commitComposer: some View {
        let selectedCount = gitStore.selectedFiles[repoPath]?.count ?? 0
        let message = gitStore.commitMessages[repoPath] ?? ""
        let canCommit = selectedCount > 0
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !gitStore.isCommitting
        return VStack(spacing: 6) {
            Rectangle().fill(Theme.border).frame(height: 1)
            TextField("Commit message…", text: Binding(
                get: { gitStore.commitMessages[repoPath] ?? "" },
                set: { gitStore.commitMessages[repoPath] = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11.5, design: .monospaced))
            .onSubmit {
                Task { await gitStore.commit(repoPath) }
            }
            Button {
                Task { await gitStore.commit(repoPath) }
            } label: {
                Text(gitStore.isCommitting ? "Committing…" : "Commit (\(selectedCount))")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accentVivid)
            .disabled(!canCommit)
        }
        .padding(10)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }
}
