import LumiKit
import LumiState
import SwiftUI

/// Source Control sekmesinin Plastic SCM sürümü (karar 45) — salt-okunur.
///
/// Başlık: branch + `cs:N` + repo@server + ↻. Gövde: Changes | History.
/// Changes çalışma alanı durumunu listeler (tıklama dosyayı açar; diff Git'e
/// özgü olduğundan sunulmaz). History son 7 günün changeset'leri; pencere
/// boşsa en yeni kayıtlar "Latest" başlığıyla gösterilir.
struct PlasticSourceControlView: View {
    enum Section: Hashable, CaseIterable {
        case changes
        case history
    }

    let repoPath: String
    @Shell private var shell
    @State private var section: Section = .changes

    private var info: PlasticWorkspaceInfo? { shell.plastic.workspaces[repoPath] }
    private var changes: [PlasticFileChange] { shell.plastic.changes[repoPath] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !shell.plastic.isCLIAvailable {
                EmptyStatePlaceholder("Plastic SCM CLI (cm) not found", density: .inline)
                Spacer(minLength: 0)
            } else {
                SegmentedModeSwitch(
                    options: Section.allCases,
                    selection: $section,
                    title: { $0 == .changes ? "Changes" : "History" },
                    accessibilityLabel: "Source control section"
                )
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.md)
                switch section {
                case .changes: changesBody
                case .history: historyBody
                }
            }
        }
        .onChange(of: repoPath) { section = .changes }
    }

    // MARK: - Başlık

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Badge(text: "Plastic SCM", color: Theme.accentPrimary)
                Spacer(minLength: 0)
                IconButton(systemName: "arrow.clockwise", label: "Refresh source control") {
                    let path = repoPath
                    Task { await shell.plastic.loadAll(path) }
                }
                .disabled(shell.plastic.isLoading(repoPath))
            }
            .frame(height: Theme.Spacing.xxxl)
            HStack(spacing: Theme.Spacing.sm) {
                Text(info?.branch ?? (info.map { "cs:\($0.changesetID)" } ?? "Not a workspace"))
                    .font(Theme.Typography.mono(.body, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if let info {
                    Text("cs:\(info.changesetID)")
                        .font(Theme.Typography.mono(.caption, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .help("Workspace changeset")
                }
            }
            if let info {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .font(Theme.Typography.ui(.caption))
                        .foregroundStyle(Theme.textMuted)
                        .accessibilityHidden(true)
                    Text(info.repositorySpec)
                        .font(Theme.Typography.mono(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
    }

    // MARK: - Changes

    private var changesBody: some View {
        VStack(spacing: 0) {
            SectionHeader(
                title: "Changes",
                count: changes.isEmpty ? nil : .warning(changes.count),
                contentPadding: Theme.Spacing.md
            )
            ScrollView {
                LazyVStack(spacing: 0) {
                    if changes.isEmpty {
                        EmptyStatePlaceholder(
                            shell.plastic.isLoading(repoPath) ? "Loading…" : "No changes — workspace clean",
                            density: .inline
                        )
                    }
                    ForEach(changes) { change in changeRow(change) }
                }
            }
        }
    }

    private func changeRow(_ change: PlasticFileChange) -> some View {
        let color = Theme.fileChangeColor(for: change.status)
        let name = (change.path as NSString).lastPathComponent
        return HoverReader { hovering in
            Button {
                if change.status != .deleted { shell.presentFile(change.path) }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    FileKindIcon(kind: FileKind.classify(name: name, isFolder: false, isExpanded: false))
                    Text(name).foregroundStyle(color).lineLimit(1)
                    Text((change.path as NSString).deletingLastPathComponent)
                        .font(Theme.Typography.ui(.caption))
                        .foregroundStyle(Theme.textMuted).lineLimit(1).truncationMode(.head)
                    Spacer(minLength: 0)
                    Text(change.status.badgeText)
                        .font(Theme.Typography.mono(.caption, weight: .medium))
                        .foregroundStyle(color)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(change.path)
            .contextMenu {
                if change.status != .deleted { Button("Open File") { shell.presentFile(change.path) } }
                Button("Reveal in Finder") { shell.reveal(change.path) }
            }
            .font(Theme.Typography.ui(.body))
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Row.compact)
            .background(hovering ? Theme.bgElevated : .clear)
        }
    }

    // MARK: - History

    private var historyBody: some View {
        let recent = shell.plastic.recentChangesets(repoPath)
        return VStack(spacing: 0) {
            SectionHeader(
                title: recent.isFallback ? "Latest changesets" : "Last 7 days",
                count: recent.items.isEmpty ? nil : .neutral(recent.items.count),
                contentPadding: Theme.Spacing.md
            )
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if recent.items.isEmpty {
                        EmptyStatePlaceholder(
                            shell.plastic.isLoading(repoPath) ? "Loading…" : "No changesets",
                            density: .inline
                        )
                    }
                    ForEach(recent.items) { changeset in changesetRow(changeset) }
                }
            }
        }
    }

    private func changesetRow(_ changeset: PlasticChangeset) -> some View {
        HoverReader { hovering in
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(changeset.comment.isEmpty ? "(no comment)" : changeset.comment)
                        .font(Theme.Typography.ui(.body))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Badge(text: changeset.branch, color: Theme.accentPrimary, style: .neutral)
                }
                HStack(spacing: Theme.Spacing.xs) {
                    Text("cs:\(changeset.changesetID)")
                        .font(Theme.Typography.mono(.caption))
                        .foregroundStyle(Theme.textSecondary)
                    Text("·").foregroundStyle(Theme.textMuted)
                    Text(changeset.owner)
                        .font(Theme.Typography.ui(.caption))
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                    Text("·").foregroundStyle(Theme.textMuted)
                    Text(RelativeTimeFormatter.label(changeset.date))
                        .font(Theme.Typography.ui(.caption))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Theme.Row.commit)
            .background(hovering ? Theme.bgElevated : Color.clear)
            .contentShape(Rectangle())
            .help(changeset.comment)
            .contextMenu {
                Button("Copy Changeset ID") { copy("\(changeset.changesetID)") }
                Button("Copy Comment") { copy(changeset.comment) }
            }
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
