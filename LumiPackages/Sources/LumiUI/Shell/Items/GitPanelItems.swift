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
                GitSectionHeader(title: "COMMITS", isExpanded: isExpanded) {
                    isExpanded.toggle()
                }
                if isExpanded {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            branches(repoPath)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private func branches(_ repoPath: String) -> some View {
        let branches = shell.git.branches[repoPath] ?? []
        if branches.isEmpty {
            GitEmptyText("No repository")
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
                    GitBadge(text: "current", color: Theme.accentPrimary)
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
    private func timeline(_ repoPath: String, branch: GitBranch) -> some View {
        let commits = shell.git.commitsByBranch[repoPath]?[branch.name] ?? []
        return VStack(alignment: .leading, spacing: 0) {
            if commits.isEmpty {
                GitEmptyText("(no branch-specific commits)").padding(.leading, 28)
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
        .padding(.leading, 16)
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
            .padding(.top, 6)
        }
    }

    private func header(_ repoPath: String) -> some View {
        let changes = shell.git.changes[repoPath] ?? []
        let selectedCount = shell.git.selectedFiles[repoPath]?.count ?? 0
        return HStack(spacing: 0) {
            GitSectionHeader(title: "CHANGES", isExpanded: isExpanded, badge: changes.count) {
                isExpanded.toggle()
            }
            if isExpanded, !changes.isEmpty {
                Button(selectedCount == changes.count ? "Deselect All" : "Select All") {
                    shell.git.toggleSelectAll(repoPath)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.accentPrimary)
                .padding(.trailing, 12)
            }
        }
    }

    @ViewBuilder
    private func changeRows(_ repoPath: String) -> some View {
        let changes = shell.git.changes[repoPath] ?? []
        if changes.isEmpty {
            GitEmptyText("No uncommitted changes")
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
        return VStack(spacing: 8) {
            Rectangle().fill(Theme.border).frame(height: 1)
            CommitMessageField(
                text: Binding(
                    get: { shell.git.commitMessage(for: repoPath) },
                    set: { shell.git.setCommitMessage($0, for: repoPath) }
                ),
                onSubmit: {
                    guard canCommit else { return }
                    Task { await shell.git.commit(repoPath) }
                }
            )
            Button {
                Task { await shell.git.commit(repoPath) }
            } label: {
                Text(shell.git.isCommitting ? "Committing…" : "Commit (\(selectedCount))")
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
}

// MARK: - Ortak parçalar

/// Collapsible bölüm başlığı (v1 CollapsibleSection).
struct GitSectionHeader: View {
    let title: String
    let isExpanded: Bool
    var badge: Int?
    let toggle: () -> Void

    init(title: String, isExpanded: Bool, badge: Int? = nil, toggle: @escaping () -> Void) {
        self.title = title
        self.isExpanded = isExpanded
        self.badge = badge
        self.toggle = toggle
    }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
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
}

struct GitBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct GitEmptyText: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Theme.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }
}

/// Commit satırı (v1 timeline): sol çizgi + nokta (HEAD yeşil+glow); başlık
/// hover'da sığmıyorsa sağdan sola kayar (MarqueeText); hover'da elevated zemin.
private struct CommitRow: View {
    let commit: GitCommit
    let isHead: Bool
    let relativeTime: String
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 0) {
                gutter
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(
                        text: commit.message,
                        font: .system(size: 12, design: .monospaced),
                        color: Theme.textPrimary,
                        animating: isHovering
                    )
                    HStack(spacing: 6) {
                        Text(commit.shortHash).foregroundStyle(Theme.accentCyan)
                        Text(commit.author).foregroundStyle(Theme.textMuted)
                        Text(relativeTime).foregroundStyle(Theme.textMuted)
                    }
                    .font(.system(size: 10, design: .monospaced))
                }
                .padding(.trailing, 10)
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? Theme.bgElevated : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
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

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Theme.accentVivid : Theme.textMuted)
            }
            .buttonStyle(.plain)

            Text(change.status.badgeText)
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
