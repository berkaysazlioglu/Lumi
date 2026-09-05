import AppKit
import LumiKit
import LumiState
import SwiftUI

/// Source Control > History: lane'li commit graph'ı (karar 40).
///
/// Veri tek `git log HEAD --topo-order` sonucudur (`GitStore.history`); lane
/// hesabı saf `CommitGraph`de, çizim `CommitGraphLaneCanvas`ta. Bu görünüm
/// yalnız satırları ve eylemleri bağlar.
struct CommitGraphView: View {
    let repoPath: String
    @Shell private var shell
    @State private var hoveredHash: String?

    private var rows: [CommitGraphRow] {
        CommitGraph.build(
            shell.git.history[repoPath] ?? [],
            headHash: shell.git.headHash[repoPath]
        )
    }

    var body: some View {
        let rows = rows
        let laneCount = CommitGraph.maxLaneCount(rows)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if rows.isEmpty {
                    EmptyStatePlaceholder("No commits", density: .inline)
                }
                ForEach(rows) { row in
                    commitRow(row, laneCount: laneCount)
                }
            }
        }
    }

    // MARK: - Satır

    private func commitRow(_ row: CommitGraphRow, laneCount: Int) -> some View {
        let commit = row.commit
        return Button { shell.presentCommit(commit) } label: {
            HStack(spacing: Theme.Spacing.sm) {
                CommitGraphLaneCanvas(row: row, laneCount: laneCount, height: Theme.Row.commit)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(commit.message)
                            .font(Theme.Typography.ui(.body))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        refBadges(commit.references, colorIndex: row.nodeColorIndex)
                    }
                    metaLine(commit)
                }
                .padding(.trailing, Theme.Spacing.md)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Theme.Row.commit)
            .background(hoveredHash == commit.hash ? Theme.bgElevated : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(commit.message)
        .onHover { hoveredHash = $0 ? commit.hash : nil }
        .contextMenu { contextMenu(commit) }
    }

    private func metaLine(_ commit: GitCommit) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(commit.shortHash)
                .font(Theme.Typography.mono(.caption))
                .foregroundStyle(Theme.textSecondary)
            Text("·").foregroundStyle(Theme.textMuted)
            Text(commit.author)
                .font(Theme.Typography.ui(.caption))
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
            Text("·").foregroundStyle(Theme.textMuted)
            Text(RelativeTimeFormatter.label(commit.date))
                .font(Theme.Typography.ui(.caption))
                .foregroundStyle(Theme.textMuted)
            Spacer(minLength: 0)
        }
        .font(Theme.Typography.ui(.caption))
        .accessibilityElement(children: .combine)
    }

    /// En fazla iki rozet + "+N" (Orca kuralı): dar sidebar'da ref listesi
    /// mesajı ezmemeli.
    @ViewBuilder
    private func refBadges(_ refs: [GitRef], colorIndex: Int) -> some View {
        let visible = refs.prefix(Self.maxVisibleRefs)
        let hidden = refs.dropFirst(Self.maxVisibleRefs)
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(Array(visible)) { ref in
                refBadge(ref, colorIndex: colorIndex)
            }
            if !hidden.isEmpty {
                Text("+\(hidden.count)")
                    .font(Theme.Typography.ui(.caption))
                    .foregroundStyle(Theme.textMuted)
                    .help(hidden.map(\.name).joined(separator: ", "))
            }
        }
        .fixedSize()
    }

    private func refBadge(_ ref: GitRef, colorIndex: Int) -> some View {
        let color = ref.isCurrent ? Theme.accentVivid : Theme.Graph.laneColor(colorIndex)
        return Text(ref.name)
            .font(Theme.Typography.ui(.caption, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.xxxs)
            .background(Theme.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(color.opacity(Self.badgeBorderOpacity), lineWidth: Theme.Stroke.hairline)
            )
            .help(Self.refHelp(ref))
    }

    // MARK: - Sağ tık menüsü

    @ViewBuilder
    private func contextMenu(_ commit: GitCommit) -> some View {
        Button("Open Commit") { shell.presentCommit(commit) }
        Divider()
        Button("Copy Commit Hash") { copy(commit.hash) }
        Button("Copy Short Hash") { copy(commit.shortHash) }
        Button("Copy Commit Message") { copy(commit.message) }
        if let url = shell.git.commitURL(repoPath, sha: commit.hash) {
            Divider()
            Button("Open on GitHub") { NSWorkspace.shared.open(url) }
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    // MARK: - Sabitler

    private static let maxVisibleRefs = 2
    private static let badgeBorderOpacity = 0.6

    private static func refHelp(_ ref: GitRef) -> String {
        switch ref.kind {
        case .head: return "Detached HEAD"
        case .localBranch: return ref.isCurrent ? "\(ref.name) (current branch)" : "\(ref.name) (branch)"
        case .remoteBranch: return "\(ref.name) (remote branch)"
        case .tag: return "\(ref.name) (tag)"
        }
    }
}

#if DEBUG
private struct CommitGraphPreview: View {
    private let repoPath = "/Users/preview/Projects/lumi"
    @State private var context = ShellContext.preview()

    var body: some View {
        CommitGraphView(repoPath: repoPath)
            .environment(\.shell, context)
            .frame(width: 360, height: 320)
            .background(Theme.bgSurface)
            .task { await context.git.loadHistory(repoPath) }
    }
}

#Preview("Commit graph") { CommitGraphPreview() }
#endif
