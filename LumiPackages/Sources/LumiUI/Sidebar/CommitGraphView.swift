import AppKit
import LumiKit
import LumiState
import SwiftUI

/// Source Control > History: lane'li commit graph'ı (karar 40, Orca paritesi
/// karar 98).
///
/// Veri tek `git log HEAD --topo-order` sonucu + upstream bağlamıdır
/// (`GitStore.historyRows`); lane/renk/sınır satırı hesabı saf `CommitGraph`te,
/// çizim `CommitGraphLaneCanvas`ta. Bu görünüm satırları, satır içi açılımı
/// (dosya listesi), hover kartını ve eylemleri bağlar.
struct CommitGraphView: View {
    let repoPath: String
    @Shell private var shell
    @State private var hoveredHash: String?
    @State private var hoverCardHash: String?
    @State private var hoverCardTask: Task<Void, Never>?
    @State private var expandedHashes: Set<String> = []

    var body: some View {
        let rows = shell.git.historyRows(repoPath)
        let laneCount = CommitGraph.maxLaneCount(rows)
        let upstream = shell.git.historyContexts[repoPath]?.upstream?.name
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if rows.isEmpty {
                    EmptyStatePlaceholder("No commits", density: .inline)
                }
                ForEach(rows) { row in
                    rowGroup(row, laneCount: laneCount, upstream: upstream)
                }
                if shell.git.historyHasMore[repoPath] == true {
                    Text("Showing the latest \(GitStore.historyLimit) commits")
                        .font(Theme.Typography.ui(.caption))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, Theme.Spacing.md)
                        .frame(height: Theme.Row.compact)
                }
            }
        }
        .overlayPreferenceValue(CommitHoverAnchorKey.self) { anchor in
            CommitHoverCardOverlay(anchor: anchor, commit: rows.first { $0.id == hoverCardHash }?.commit)
                .animation(Theme.Motion.quickEase, value: hoverCardHash)
        }
        .onChange(of: repoPath) {
            expandedHashes = []
            setHover(nil)
        }
        .onDisappear { hoverCardTask?.cancel() }
    }

    // MARK: - Satır + açılım

    @ViewBuilder
    private func rowGroup(_ row: CommitGraphRow, laneCount: Int, upstream: String?) -> some View {
        let isExpanded = !row.isBoundary && expandedHashes.contains(row.id)
        GitHistoryRowView(
            row: row,
            laneCount: laneCount,
            upstream: upstream,
            isExpanded: isExpanded,
            isHovered: hoveredHash == row.id,
            onToggle: { toggle(row.commit) }
        )
        .onHover { inside in
            guard !row.isBoundary else { return }
            if inside { setHover(row.id) } else if hoveredHash == row.id { setHover(nil) }
        }
        .anchorPreference(key: CommitHoverAnchorKey.self, value: .bounds) { anchor in
            hoverCardHash == row.id ? anchor : nil
        }
        .contextMenu {
            if !row.isBoundary { contextMenu(row.commit) }
        }
        if isExpanded {
            GitCommitFilesView(
                row: row,
                laneCount: laneCount,
                files: shell.git.commitFiles[repoPath]?[row.id],
                onOpenFile: { shell.presentCommit(row.commit, file: $0) },
                onOpenAll: { shell.presentCommit(row.commit) }
            )
        }
    }

    private func toggle(_ commit: GitCommit) {
        // Tıklama kartı kapatır ama satır hover'da kalır (imleç hâlâ üstünde).
        hoverCardTask?.cancel()
        hoverCardHash = nil
        if expandedHashes.remove(commit.hash) == nil {
            expandedHashes.insert(commit.hash)
            Task { await shell.git.loadCommitFiles(repoPath, sha: commit.hash) }
        }
    }

    /// Satır hover'ı anında, kart `hoverCardDelay` sonra; satırdan çıkınca
    /// ikisi birden kapanır.
    private func setHover(_ hash: String?) {
        hoveredHash = hash
        hoverCardTask?.cancel()
        hoverCardHash = nil
        guard let hash else { return }
        hoverCardTask = Task { @MainActor in
            try? await Task.sleep(for: Theme.Graph.hoverCardDelay)
            guard !Task.isCancelled, hoveredHash == hash else { return }
            hoverCardHash = hash
        }
    }

    // MARK: - Sağ tık menüsü

    @ViewBuilder
    private func contextMenu(_ commit: GitCommit) -> some View {
        Button("Open Commit") { shell.presentCommit(commit) }
        Divider()
        Button("Copy Commit Hash") { copy(commit.hash) }
        Button("Copy Short Hash") { copy(commit.shortHash) }
        Button("Copy Commit Message") { copy(commit.fullMessage) }
        if let url = shell.git.commitURL(repoPath, sha: commit.hash) {
            Divider()
            Button("Open on GitHub") { NSWorkspace.shared.open(url) }
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
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
