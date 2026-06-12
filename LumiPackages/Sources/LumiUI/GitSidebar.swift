import LumiKit
import LumiState
import SwiftUI

/// Sağ sidebar: Commits (branch + timeline) + Changes (status + commit akışı).
/// Görünüm v1 git paneliyle birebir (spec/12 §2-5 davranışı, spec/21 §16).
struct GitSidebar: View {
    let repoPath: String
    let gitStore: GitStore
    let onSelectCommit: (GitCommit) -> Void
    let onShowFileDiff: (String) -> Void

    @State private var commitsExpanded = true
    @State private var changesExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    commitsSection
                    Rectangle().fill(Theme.border).frame(height: 1)
                    changesSection
                }
            }
            commitComposer
        }
        .background(Theme.bgSurface)
    }

    // MARK: - Collapsible bölüm başlığı (v1 CollapsibleSection)

    private func sectionHeader(
        _ title: String,
        expanded: Bool,
        badge: Int? = nil,
        toggle: @escaping () -> Void
    ) -> some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .kerning(0.5)
                    .foregroundStyle(Theme.textSecondary)
                if let badge {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.warning)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Theme.warning.opacity(0.2))
                        .clipShape(Capsule())
                }
                Spacer()
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Commits (branch + timeline)

    private var commitsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("COMMITS", expanded: commitsExpanded) {
                commitsExpanded.toggle()
            }
            if commitsExpanded {
                let branches = gitStore.branches[repoPath] ?? []
                if branches.isEmpty {
                    emptyText("No repository")
                }
                ForEach(branches) { branch in
                    branchRow(branch)
                    if gitStore.isBranchExpanded(repoPath, name: branch.name) {
                        commitTimeline(for: branch)
                    }
                }
            }
        }
        .padding(.bottom, 6)
    }

    private func branchRow(_ branch: GitBranch) -> some View {
        Button {
            gitStore.toggleBranch(repoPath, name: branch.name)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: gitStore.isBranchExpanded(repoPath, name: branch.name)
                    ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12))
                    .foregroundStyle(branch.isCurrent ? Theme.accentPrimary : Theme.textMuted)
                Text(branch.name)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(branch.isCurrent ? Theme.accentPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if branch.isCurrent {
                    badge("current", color: Theme.accentPrimary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Timeline: sol dikey çizgi + her commit'te nokta (HEAD = en üst commit,
    /// yeşil + glow); hash cyan, mesaj primary, tarih muted (v1 paritesi).
    private func commitTimeline(for branch: GitBranch) -> some View {
        let commits = gitStore.commitsByBranch[repoPath]?[branch.name] ?? []
        return VStack(alignment: .leading, spacing: 0) {
            if commits.isEmpty {
                emptyText("(no branch-specific commits)").padding(.leading, 28)
            }
            ForEach(Array(commits.enumerated()), id: \.element.id) { index, commit in
                Button {
                    onSelectCommit(commit)
                } label: {
                    HStack(alignment: .top, spacing: 0) {
                        timelineGutter(isHead: branch.isCurrent && index == 0)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(commit.message)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(commit.shortHash)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.accentCyan)
                                Text(commit.author)
                                    .foregroundStyle(Theme.textMuted)
                                Text(Self.relativeTime(commit.date))
                                    .foregroundStyle(Theme.textMuted)
                            }
                            .font(.system(size: 10, design: .monospaced))
                        }
                        .padding(.trailing, 10)
                        .padding(.vertical, 4)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 16)
    }

    private func timelineGutter(isHead: Bool) -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Theme.border)
                .frame(width: 1)
                .padding(.leading, 9)
            Circle()
                .fill(isHead ? Theme.success : Theme.border)
                .frame(width: 7, height: 7)
                .shadow(color: isHead ? Theme.success.opacity(0.8) : .clear, radius: 4)
                .padding(.leading, 6)
                .padding(.top, 6)
        }
        .frame(width: 28, alignment: .topLeading)
    }

    // MARK: - Changes

    private var changesSection: some View {
        let changes = gitStore.changes[repoPath] ?? []
        let selectedCount = gitStore.selectedFiles[repoPath]?.count ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                sectionHeader("CHANGES", expanded: changesExpanded, badge: changes.count) {
                    changesExpanded.toggle()
                }
                if changesExpanded, !changes.isEmpty {
                    Button(selectedCount == changes.count ? "Deselect All" : "Select All") {
                        gitStore.toggleSelectAll(repoPath)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.accentPrimary)
                    .padding(.trailing, 12)
                }
            }
            if changesExpanded {
                if changes.isEmpty {
                    emptyText("No uncommitted changes")
                }
                ForEach(changes) { change in
                    FileChangeRow(
                        change: change,
                        isSelected: gitStore.isSelected(repoPath, path: change.path),
                        onToggle: { gitStore.toggleFile(repoPath, path: change.path) },
                        onShowDiff: { onShowFileDiff(change.path) }
                    )
                }
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Commit composer (v1: bgDeep input + focus halkası + mor buton)

    private var commitComposer: some View {
        let selectedCount = gitStore.selectedFiles[repoPath]?.count ?? 0
        let message = gitStore.commitMessages[repoPath] ?? ""
        let canCommit = selectedCount > 0
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !gitStore.isCommitting
        return VStack(spacing: 8) {
            Rectangle().fill(Theme.border).frame(height: 1)
            CommitMessageField(
                text: Binding(
                    get: { gitStore.commitMessages[repoPath] ?? "" },
                    set: { gitStore.commitMessages[repoPath] = $0 }
                ),
                onSubmit: { if canCommit { Task { await gitStore.commit(repoPath) } } }
            )
            Button {
                Task { await gitStore.commit(repoPath) }
            } label: {
                Text(gitStore.isCommitting ? "Committing…" : "Commit (\(selectedCount))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Theme.accentVivid)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .opacity(canCommit ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!canCommit)
        }
        .padding(10)
    }

    // MARK: - Yardımcılar

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Theme.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
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
}

/// Dosya değişiklik satırı (v1 FileChangeItem): checkbox + status kutusu +
/// dosya adı + hover'da beliren diff (eye) butonu; hover'da elevated zemin.
private struct FileChangeRow: View {
    let change: GitFileChange
    let isSelected: Bool
    let onToggle: () -> Void
    let onShowDiff: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Theme.accentVivid : Theme.textMuted)
            }
            .buttonStyle(.plain)

            Text(change.status.badge)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.fileChangeColor(for: change.status))
                .frame(width: 16, height: 16)

            Text((change.path as NSString).lastPathComponent)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(change.path)

            Spacer(minLength: 0)

            Button(action: onShowDiff) {
                Image(systemName: "eye")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .help("Show diff")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isHovering ? Theme.bgElevated : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onHover { isHovering = $0 }
    }
}

/// Commit mesajı alanı (v1: bgDeep zemin, odakta mor kenarlık).
private struct CommitMessageField: View {
    @Binding var text: String
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Commit message…", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Theme.textPrimary)
            .focused($isFocused)
            .onSubmit(onSubmit)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.bgDeep)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isFocused ? Theme.accentVivid : Theme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
