import AppKit
import LumiKit
import LumiState
import SwiftUI

/// Source Control başlığı (Orca paritesi, karar 41):
///
/// ```
/// [⎇ Create PR]                       [↻] [⋯]
/// main                          +4,612 -691
/// → origin/main                    ↑2 ↓1 [↗]
/// ```
///
/// Satır istatistiği çalışma ağacının HEAD'e göre farkıdır; ok sayaçları
/// upstream'e göre ileri/geri commit'lerdir. Upstream yoksa ikinci satır
/// "Not published" der — push kapsam dışı olduğu için eylem sunmaz.
struct SourceControlHeader: View {
    let repoPath: String
    @Shell private var shell
    @State private var refreshing = false
    @State private var showsMenu = false

    private var branch: GitBranch? { shell.git.branches[repoPath]?.first { $0.isCurrent } }
    private var summary: GitBranchSummary? { shell.git.branchSummaries[repoPath] }
    private var repoURL: URL? { shell.git.remoteURLs[repoPath].flatMap(GitRemote.webURL) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            toolbar
            branchRow
            upstreamRow
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
    }

    // MARK: - Üst şerit

    private var toolbar: some View {
        HStack(spacing: Theme.Spacing.xs) {
            createPullRequestButton
            Spacer(minLength: 0)
            IconButton(systemName: "arrow.clockwise", label: "Refresh source control") {
                let path = repoPath
                refreshing = true
                Task { await shell.git.refresh(path); refreshing = false }
            }
            .disabled(refreshing)
            IconButton(systemName: "ellipsis", label: "Source control actions", size: .body) {
                showsMenu.toggle()
            }
            .popover(isPresented: $showsMenu, arrowEdge: .bottom) {
                PopoverMenu(items: menuItems, dismiss: { showsMenu = false })
            }
        }
        .frame(height: Theme.Spacing.xxxl)
    }

    private var menuItems: [PopoverMenu.Item] {
        let changes = shell.git.changes[repoPath] ?? []
        let selected = shell.git.selectedFiles[repoPath]?.count ?? 0
        return [
            .action(selected == changes.count ? "Deselect All" : "Select All", icon: "checklist",
                    isEnabled: !changes.isEmpty) { shell.git.toggleSelectAll(repoPath) },
            .divider,
            .action("Copy Branch Name", icon: "doc.on.doc", isEnabled: branch != nil) {
                if let name = branch?.name { copy(name) }
            },
            .action("Open Repository on GitHub", icon: "arrow.up.right.square", isEnabled: repoURL != nil) {
                if let repoURL { NSWorkspace.shared.open(repoURL) }
            },
            .action("Reveal in Finder", icon: "folder") { shell.reveal("") },
        ]
    }

    // MARK: - Branch satırı

    private var branchRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(branch?.name ?? "No commits yet")
                .font(Theme.Typography.mono(.body, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if let summary, summary.hasLineChanges {
                lineStats(summary)
            }
        }
    }

    private func lineStats(_ summary: GitBranchSummary) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text("+\(summary.insertions.formatted())")
                .foregroundStyle(Theme.success)
            Text("-\(summary.deletions.formatted())")
                .foregroundStyle(Theme.error)
        }
        .font(Theme.Typography.mono(.caption, weight: .medium))
        .monospacedDigit()
        .help("Uncommitted line changes")
        .accessibilityLabel("\(summary.insertions) insertions, \(summary.deletions) deletions")
    }

    // MARK: - Upstream satırı

    @ViewBuilder
    private var upstreamRow: some View {
        if branch != nil {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "arrow.right")
                    .font(Theme.Typography.ui(.caption))
                    .foregroundStyle(Theme.textMuted)
                    .accessibilityHidden(true)
                Text(summary?.upstream ?? "Not published")
                    .font(Theme.Typography.mono(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if let summary, summary.upstream != nil { aheadBehind(summary) }
                if let repoURL {
                    IconButton(systemName: "arrow.up.right.square", label: "Open repository on GitHub", size: .caption) {
                        NSWorkspace.shared.open(repoURL)
                    }
                }
            }
        }
    }

    private func aheadBehind(_ summary: GitBranchSummary) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            if summary.ahead > 0 { Text("↑\(summary.ahead)") }
            if summary.behind > 0 { Text("↓\(summary.behind)") }
            if summary.ahead == 0 && summary.behind == 0 {
                Image(systemName: "checkmark").accessibilityHidden(true)
            }
        }
        .font(Theme.Typography.mono(.caption))
        .foregroundStyle(Theme.textMuted)
        .help("\(summary.ahead) ahead, \(summary.behind) behind \(summary.upstream ?? "upstream")")
        .accessibilityLabel("\(summary.ahead) commits ahead, \(summary.behind) behind")
    }

    // MARK: - Create PR (karar 40)

    /// Yalnız GitHub remote'lu ve default branch DIŞINDA bir branch checkout
    /// edilmiş repolarda görünür. `gh` yoksa buton kalır ama kapalıdır —
    /// kaybolması "neden yok?" sorusunu doğuruyordu.
    @ViewBuilder
    private var createPullRequestButton: some View {
        if let branch = shell.git.pullRequestBranch(repoPath) {
            let hasCLI = shell.git.isGitHubCLIAvailable
            Button { createPullRequest(for: branch) } label: {
                Label("Create PR", systemImage: "arrow.triangle.pull")
                    .labelStyle(.titleAndIcon)
                    .font(Theme.Typography.ui(.label, weight: .medium))
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
            }
            .buttonStyle(
                HoverButtonStyle(
                    foreground: hasCLI ? Theme.textPrimary : Theme.textMuted,
                    hoverForeground: Theme.textPrimary,
                    background: Theme.bgElevated,
                    hoverBackground: Theme.border
                )
            )
            .disabled(!hasCLI)
            .help(hasCLI ? "Open a GitHub pull request for \(branch)" : "GitHub CLI (gh) not found")
        }
    }

    /// PR formu tarayıcıda açılır (`--web`): başlık/gövde düzenlemesi Lumi'ye
    /// taşınmaz (kapsam dışı), komut kullanıcının gördüğü bir terminalde koşar
    /// ki `gh auth` istemi görünür olsun.
    private func createPullRequest(for branch: String) {
        let escaped = branch.replacingOccurrences(of: "'", with: "'\\''")
        shell.terminals.spawn(in: repoPath, command: "gh pr create --web --head '\(escaped)'")
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
