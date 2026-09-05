import LumiKit
import LumiState
import SwiftUI

/// Git panelinin iki panel öğesi (Faz 6.2 — eski tek parça `GitSidebar`):
/// `.gitCommits` (branch + commit zaman çizelgesi) ve `.gitChanges`
/// (çalışma kopyası değişiklikleri + commit composer).
///
/// İkisi de bağımsız birer öğedir: kullanıcı `LayoutStore.move(item:to:)` ile
/// birini sola, diğerini sağda bırakabilir. Parent closure'ları kalktı —
/// commit/diff sunumu `ShellContext` üzerinden akar.

// MARK: - Commits

public struct GitCommitsPanelItem: View {
    @Shell private var shell

    @State private var isExpanded = true

    public init() {}

    public var body: some View {
        if let repoPath = shell.activeRepoPath {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(
                    title: "Commits",
                    disclosure: .leading,
                    isExpanded: isExpanded,
                    contentPadding: Theme.Spacing.lg,
                    onToggle: { isExpanded.toggle() }
                )
                if isExpanded {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            branches(repoPath)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, Theme.Spacing.sm)
        }
    }

    @ViewBuilder
    private func branches(_ repoPath: String) -> some View {
        let branches = shell.git.branches[repoPath] ?? []
        if branches.isEmpty {
            EmptyStatePlaceholder("No repository", density: .inline)
        }
        ForEach(branches) { branch in
            branchRow(repoPath, branch: branch)
            if shell.git.isBranchExpanded(repoPath, name: branch.name) {
                timeline(repoPath, branch: branch)
            }
        }
    }

    private func branchRow(_ repoPath: String, branch: GitBranch) -> some View {
        Button {
            shell.git.toggleBranch(repoPath, name: branch.name)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: shell.git.isBranchExpanded(repoPath, name: branch.name)
                    ? "chevron.down" : "chevron.right")
                    .font(Theme.Typography.ui(.tiny, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                    .accessibilityHidden(true)
                Image(systemName: "arrow.triangle.branch")
                    .font(Theme.Typography.ui(.body))
                    .foregroundStyle(branch.isCurrent ? Theme.accentPrimary : Theme.textMuted)
                    .accessibilityHidden(true)
                Text(branch.name)
                    .font(Theme.Typography.mono(.body))
                    .foregroundStyle(branch.isCurrent ? Theme.accentPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if branch.isCurrent {
                    Badge(text: "current")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Branch \(branch.name)")
    }

    /// Timeline: sol dikey çizgi + her commit'te nokta (HEAD = en üst commit,
    /// yeşil + glow); hash cyan, mesaj primary, tarih muted (v1 paritesi).
    private func timeline(_ repoPath: String, branch: GitBranch) -> some View {
        let commits = shell.git.commitsByBranch[repoPath]?[branch.name] ?? []
        return VStack(alignment: .leading, spacing: 0) {
            if commits.isEmpty {
                EmptyStatePlaceholder("(no branch-specific commits)", density: .inline)
                    .padding(.leading, 28)
            }
            ForEach(Array(commits.enumerated()), id: \.element.id) { index, commit in
                CommitRow(
                    commit: commit,
                    isHead: branch.isCurrent && index == 0,
                    relativeTime: RelativeTimeFormatter.label(commit.date),
                    onSelect: { shell.presentCommit(commit) }
                )
            }
        }
        .padding(.leading, Theme.Spacing.xl)
    }
}

// MARK: - Changes + commit composer

public struct GitChangesPanelItem: View {
    @Shell private var shell

    @State private var isExpanded = true

    public init() {}

    public var body: some View {
        if let repoPath = shell.activeRepoPath {
            VStack(spacing: 0) {
                header(repoPath)
                if isExpanded {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            changeRows(repoPath)
                        }
                    }
                }
                Spacer(minLength: 0)
                composer(repoPath)
            }
            .padding(.top, Theme.Spacing.sm)
        }
    }

    private func header(_ repoPath: String) -> some View {
        let changes = shell.git.changes[repoPath] ?? []
        let selectedCount = shell.git.selectedFiles[repoPath]?.count ?? 0
        return SectionHeader(
            title: "Changes",
            count: .warning(changes.count),
            disclosure: .leading,
            isExpanded: isExpanded,
            contentPadding: Theme.Spacing.lg,
            onToggle: { isExpanded.toggle() }
        ) {
            if isExpanded, !changes.isEmpty {
                Button(selectedCount == changes.count ? "Deselect All" : "Select All") {
                    shell.git.toggleSelectAll(repoPath)
                }
                .buttonStyle(.plain)
                .font(Theme.Typography.mono(.caption))
                .foregroundStyle(Theme.accentPrimary)
            }
        }
    }

    @ViewBuilder
    private func changeRows(_ repoPath: String) -> some View {
        let changes = shell.git.changes[repoPath] ?? []
        if changes.isEmpty {
            EmptyStatePlaceholder("No uncommitted changes", density: .inline)
        }
        ForEach(changes) { change in
            FileChangeRow(
                change: change,
                isSelected: shell.git.isSelected(repoPath, path: change.path),
                onToggle: { shell.git.toggleFile(repoPath, path: change.path) },
                onShowDiff: { shell.presentDiff(change.path) }
            )
        }
    }

    /// Commit composer (v1: bgDeep input + focus halkası + mor buton).
    /// Kural (`canCommit`) ve taslak mesaj artık `GitStore`'un işi — view yalnız
    /// okur/intent çağırır (refactor 5.4 + 6.7).
    private func composer(_ repoPath: String) -> some View {
        let selectedCount = shell.git.selectedFiles[repoPath]?.count ?? 0
        let canCommit = shell.git.canCommit(repoPath)
        return VStack(spacing: Theme.Spacing.md) {
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
            LumiTextInput(
                text: Binding(
                    get: { shell.git.commitMessage(for: repoPath) },
                    set: { shell.git.setCommitMessage($0, for: repoPath) }
                ),
                placeholder: "Commit message…",
                onSubmit: {
                    guard canCommit else { return }
                    Task { await shell.git.commit(repoPath) }
                }
            )
            Button {
                Task { await shell.git.commit(repoPath) }
            } label: {
                Text(shell.git.isCommitting ? "Committing…" : "Commit (\(selectedCount))")
                    .font(Theme.Typography.mono(.body, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7) // ölçek dışı ara değer (v1 paritesi)
                    .background(Theme.accentVivid)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    .opacity(canCommit ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!canCommit)
        }
        // 10pt: ölçek dışı ara değer (v1 paritesi korunuyor).
        .padding(10)
    }
}

// MARK: - Ortak parçalar

/// Commit satırı (v1 timeline): sol çizgi + nokta (HEAD yeşil+glow); başlık
/// hover'da sığmıyorsa sağdan sola kayar (MarqueeText); hover'da elevated zemin.
private struct CommitRow: View {
    let commit: GitCommit
    let isHead: Bool
    let relativeTime: String
    let onSelect: () -> Void

    var body: some View {
        HoverReader { isHovering in
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 0) {
                    gutter
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        MarqueeText(
                            text: commit.message,
                            font: Theme.Typography.mono(.body),
                            color: Theme.textPrimary,
                            animating: isHovering
                        )
                        HStack(spacing: Theme.Spacing.sm) {
                            Text(commit.shortHash).foregroundStyle(Theme.accentCyan)
                            Text(commit.author).foregroundStyle(Theme.textMuted)
                            Text(relativeTime).foregroundStyle(Theme.textMuted)
                        }
                        .font(Theme.Typography.mono(.caption))
                    }
                    // 10pt: ölçek dışı ara değer (v1 paritesi korunuyor).
                    .padding(.trailing, 10)
                    .padding(.vertical, Theme.Spacing.xs)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isHovering ? Theme.bgElevated : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityLabel("Commit \(commit.shortHash): \(commit.message)")
    }

    private var gutter: some View {
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
}

/// Dosya değişiklik satırı (v1 FileChangeItem): checkbox + status kutusu +
/// dosya adı + hover'da beliren diff (eye) butonu; hover'da elevated zemin.
private struct FileChangeRow: View {
    let change: GitFileChange
    let isSelected: Bool
    let onToggle: () -> Void
    let onShowDiff: () -> Void

    var body: some View {
        HoverReader { isHovering in
            HStack(spacing: Theme.Spacing.md) {
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(Theme.Typography.ui(.body))
                        .foregroundStyle(isSelected ? Theme.accentVivid : Theme.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stage \(change.path)")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])

                Text(change.status.badgeText)
                    .font(Theme.Typography.mono(.caption, weight: .bold))
                    .foregroundStyle(Theme.fileChangeColor(for: change.status))
                    .frame(width: Theme.Spacing.xl, height: Theme.Spacing.xl)

                Text((change.path as NSString).lastPathComponent)
                    .font(Theme.Typography.mono(.body))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(change.path)

                Spacer(minLength: 0)

                IconButton(
                    systemName: "eye",
                    label: "Show diff for \(change.path)",
                    size: .body,
                    weight: .regular,
                    side: 22,
                    showsHoverBackground: false,
                    action: onShowDiff
                )
                .opacity(isHovering ? 1 : 0)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.xs)
            .background(isHovering ? Theme.bgElevated : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
    }
}

#if DEBUG
#Preview("Git panels") {
    HStack(spacing: 0) {
        GitCommitsPanelItem()
        GitChangesPanelItem()
    }
    .frame(width: 560, height: 420)
    .background(Theme.bgSurface)
    .environment(\.shell, ShellContext.preview())
}
#endif
