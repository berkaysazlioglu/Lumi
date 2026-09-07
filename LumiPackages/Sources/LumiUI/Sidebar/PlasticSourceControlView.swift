import LumiKit
import LumiState
import SwiftUI

/// Source Control sekmesinin Plastic SCM sürümü (karar 46).
///
/// Başlık: branch + `cs:N` + repo@server + ↻. Gövde: Changes | History.
/// Changes: mesaj kutusu + Check in butonu, seçim kutulu dosya listesi
/// (tıklama dosyayı açar; diff Git'e özgü olduğundan sunulmaz), sağ tık
/// Undo Changes / Move to Trash. History: son 7 günün changeset'leri Git ile
/// aynı lane graph'ında (`PlasticHistoryGraph` → `CommitGraph`); pencere
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
    private var selectedCount: Int { shell.plastic.selectedFiles[repoPath]?.count ?? 0 }

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
                Text(info?.branch.map(PlasticBranchName.display) ?? (info.map { "cs:\($0.changesetID)" } ?? "Not a workspace"))
                    .font(Theme.Typography.mono(.body, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(info?.branch ?? "")
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
            composer
                .padding(.horizontal, Theme.Spacing.md)
            // `trailing:` etiketi ZORUNLU: etiketsiz trailing closure ilk closure
            // parametresi olan `onToggle`a bağlanıyordu — düğme hiç çizilmiyor,
            // başlık tıklanabilir görünüyordu (release build uyarısı bunu yakaladı).
            SectionHeader(
                title: "Changes",
                count: changes.isEmpty ? nil : .warning(changes.count),
                contentPadding: Theme.Spacing.md,
                trailing: {
                    if !changes.isEmpty {
                        Button(selectedCount == changes.count ? "Deselect All" : "Select All") {
                            shell.plastic.toggleSelectAll(repoPath)
                        }
                        .buttonStyle(.plain)
                        .font(Theme.Typography.ui(.caption))
                        .foregroundStyle(Theme.textSecondary)
                    }
                }
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

    private var composer: some View {
        VStack(spacing: Theme.Spacing.md) {
            CommitMessageField(
                placeholder: "Comment",
                text: Binding(
                    get: { shell.plastic.checkinMessage(for: repoPath) },
                    set: { shell.plastic.setCheckinMessage($0, for: repoPath) }
                ),
                isGenerating: shell.commitAssistant.isGenerating(repoPath),
                canGenerate: selectedCount > 0,
                onGenerate: {
                    let path = repoPath
                    Task { await shell.generatePlasticCheckinMessage(path) }
                }
            )
            checkinButton
        }
        .padding(.bottom, Theme.Spacing.sm)
    }

    /// Sabit yükseklikli (`Row.control`) checkin butonu — Git'teki Commit
    /// butonuyla aynı geometri; bölünmüş menü yok (seçim eylemleri başlıkta).
    private var checkinButton: some View {
        let canCheckin = shell.plastic.canCheckin(repoPath)
        return Button {
            Task { await shell.plastic.checkin(repoPath) }
        } label: {
            Label(
                shell.plastic.isCheckingIn ? "Checking in…" : "Check in (\(selectedCount))",
                systemImage: shell.plastic.isCheckingIn ? "hourglass" : "checkmark"
            )
            .font(Theme.Typography.ui(.body, weight: .medium))
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Row.control)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canCheckin)
        .foregroundStyle(canCheckin ? Theme.textPrimary : Theme.textMuted)
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
        )
        .help("Check in selected items as one changeset")
    }

    private func changeRow(_ change: PlasticFileChange) -> some View {
        let color = Theme.fileChangeColor(for: change.status)
        let name = (change.path as NSString).lastPathComponent
        return HoverReader { hovering in
            HStack(spacing: Theme.Spacing.sm) {
                Button { shell.plastic.toggleFile(repoPath, path: change.path) } label: {
                    Image(systemName: shell.plastic.isSelected(repoPath, path: change.path) ? "checkmark.square.fill" : "square")
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Include \(change.path) in check-in")
                .accessibilityLabel("Include \(change.path) in check-in")
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
                .contextMenu { changeContextMenu(change) }
            }
            .font(Theme.Typography.ui(.body))
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Row.compact)
            .background(hovering ? Theme.bgElevated : .clear)
        }
    }

    /// Private (kontrolsüz) öğede `cm undo` etkisizdir → çöpe taşıma sunulur;
    /// diğerlerinde Undo Changes yerel değişikliği atar (geri alınamaz, Plastic
    /// uyarısı) — bu yüzden `.destructive` rol.
    @ViewBuilder
    private func changeContextMenu(_ change: PlasticFileChange) -> some View {
        if change.status != .deleted { Button("Open File") { shell.presentFile(change.path) } }
        Button("Reveal in Finder") { shell.reveal(change.path) }
        Divider()
        if change.status == .untracked {
            Button("Move to Trash", role: .destructive) { shell.trash(change.path) }
        } else {
            Button("Undo Changes", role: .destructive) {
                let path = change.path
                Task { await shell.plastic.undo(repoPath, path: path) }
            }
        }
    }

    // MARK: - History

    private var historyBody: some View {
        let recent = shell.plastic.recentChangesets(repoPath)
        let rows = CommitGraph.build(
            PlasticHistoryGraph.commits(from: recent.items, currentBranch: info?.branch),
            headHash: PlasticHistoryGraph.headHash(workspaceChangesetID: info?.changesetID, in: recent.items)
        )
        let laneCount = CommitGraph.maxLaneCount(rows)
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
                    ForEach(rows) { row in changesetRow(row, laneCount: laneCount) }
                }
            }
        }
    }

    /// Git History satırıyla aynı düzen: lane kanvası + yorum + ref rozetleri
    /// (branch uçları) + `cs:N · owner · süre`. `row.commit` Plastic
    /// changeset'inin `GitCommit` projeksiyonudur (`shortHash` = `cs:N`).
    private func changesetRow(_ row: CommitGraphRow, laneCount: Int) -> some View {
        let commit = row.commit
        return HoverReader { hovering in
            HStack(spacing: Theme.Spacing.sm) {
                CommitGraphLaneCanvas(row: row, laneCount: laneCount, height: Theme.Row.commit)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(commit.message.isEmpty ? "(no comment)" : commit.message)
                            .font(Theme.Typography.ui(.body))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        CommitRefBadges(
                            refs: commit.references,
                            colorIndex: row.nodeColorIndex,
                            displayName: { PlasticBranchName.display($0.name) },
                            marqueeMaxWidth: Theme.Graph.refBadgeMaxWidth
                        )
                    }
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
                    }
                }
                .padding(.trailing, Theme.Spacing.md)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Theme.Row.commit)
            .background(hovering ? Theme.bgElevated : Color.clear)
            .contentShape(Rectangle())
            .help(commit.message)
            .contextMenu {
                Button("Copy Changeset ID") { copy(commit.hash) }
                Button("Copy Comment") { copy(commit.message) }
            }
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
