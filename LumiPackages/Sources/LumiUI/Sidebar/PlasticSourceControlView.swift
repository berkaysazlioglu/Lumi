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
    @State private var changesQuery = ""
    @State private var collapsedGroups: Set<PlasticChangeGroup.Kind> = []

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
        let groups = shell.plastic.changeGroups(repoPath, query: changesQuery)
        return VStack(spacing: 0) {
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
            if !changes.isEmpty {
                searchField
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.sm)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if changes.isEmpty {
                        EmptyStatePlaceholder(
                            shell.plastic.isLoading(repoPath) ? "Loading…" : "No changes — workspace clean",
                            density: .inline
                        )
                    } else if groups.isEmpty {
                        EmptyStatePlaceholder("No items match “\(changesQuery)”", density: .inline)
                    }
                    ForEach(groups) { group in
                        groupHeader(group)
                        if !collapsedGroups.contains(group.kind) {
                            ForEach(group.items) { change in changeRow(change) }
                        }
                    }
                }
            }
        }
    }

    /// Ad VEYA yol üzerinde alt dize araması (Explorer'daki alan biçimi).
    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.ui(.body))
                .foregroundStyle(Theme.textMuted)
                .accessibilityHidden(true)
            TextField("Filter by name or path…", text: $changesQuery)
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
                .font(Theme.Typography.ui(.body))
            if !changesQuery.isEmpty {
                IconButton(systemName: "xmark", label: "Clear filter", size: .caption) { changesQuery = "" }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Spacing.xxxl - Theme.Spacing.xs)
        .background(Theme.bgDeep)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
        )
    }

    /// Plastic GUI grup satırı: `› [☑] [C] Changed items - 12 of 13 items selected`.
    /// Kutu üç durumlu (hepsi / kısmi / hiçbiri); tıklama grubun tamamını çevirir.
    private func groupHeader(_ group: PlasticChangeGroup) -> some View {
        let color = Theme.fileChangeColor(for: group.kind.representativeStatus)
        let isCollapsed = collapsedGroups.contains(group.kind)
        return HoverReader { hovering in
            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    if isCollapsed { collapsedGroups.remove(group.kind) } else { collapsedGroups.insert(group.kind) }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(Theme.Typography.ui(.caption, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: Theme.Spacing.lg)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "Expand \(group.kind.title)" : "Collapse \(group.kind.title)")
                .accessibilityLabel(isCollapsed ? "Expand \(group.kind.title)" : "Collapse \(group.kind.title)")
                Button { shell.plastic.toggleSelection(repoPath, paths: group.paths) } label: {
                    Image(systemName: group.isFullySelected ? "checkmark.square.fill" : (group.isPartiallySelected ? "minus.square.fill" : "square"))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help(group.isFullySelected ? "Deselect all \(group.kind.title.lowercased())" : "Select all \(group.kind.title.lowercased())")
                .accessibilityLabel("Select all \(group.kind.title.lowercased())")
                Badge(text: group.kind.badgeLetter, color: color, size: .caption, weight: .bold)
                Text("\(group.kind.title) - \(group.selectedCount) of \(group.items.count) items selected")
                    .font(Theme.Typography.ui(.body, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Row.control)
            // Grup başlığı hover'dan bağımsız yükseltilmiş zemin alır: dosya
            // satırlarından hiyerarşi olarak ayrılsın (genişlik maliyeti yok).
            .background(hovering ? Theme.border : Theme.bgElevated)
            .contentShape(Rectangle())
            .contextMenu { groupContextMenu(group) }
        }
    }

    @ViewBuilder
    private func groupContextMenu(_ group: PlasticChangeGroup) -> some View {
        Button(group.isFullySelected ? "Deselect All in Group" : "Select All in Group") {
            shell.plastic.toggleSelection(repoPath, paths: group.paths)
        }
        Divider()
        undoMenuItems
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
                        // Ad önce yer alır (layoutPriority): daralan alanı yol kısaltır, ad değil.
                        Text(name).foregroundStyle(color).lineLimit(1).layoutPriority(1)
                        Text((change.path as NSString).deletingLastPathComponent)
                            .font(Theme.Typography.ui(.caption))
                            .foregroundStyle(Theme.textMuted).lineLimit(1).truncationMode(.head)
                        Spacer(minLength: 0)
                        // Durum harfi YOK: grup başlığı zaten söylüyor; kazanılan
                        // genişlik yola kalır (renk adda sürer).
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(change.path) (\(change.status.badgeText))")
                .contextMenu { changeContextMenu(change) }
            }
            .font(Theme.Typography.ui(.body))
            .padding(.leading, Self.fileRowIndent)
            .padding(.trailing, Theme.Spacing.md)
            .frame(height: Theme.Row.compact)
            .background(hovering ? Theme.bgElevated : .clear)
            // Girinti kılavuzu: grup chevron'unun merkezinden inen hairline —
            // dosya/grup ayrımını genişlik harcamadan gösterir.
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: Theme.Stroke.hairline)
                    .padding(.leading, Self.indentGuideOffset)
            }
        }
    }

    /// Private (kontrolsüz) öğede `cm undo` etkisizdir → çöpe taşıma sunulur;
    /// diğerlerinde Undo Changes yerel değişikliği atar (geri alınamaz, Plastic
    /// uyarısı) — bu yüzden `.destructive` rol. Seçim birden fazlaysa toplu
    /// undo ve çalışma alanı geneli "Undo Unchanged" de sunulur.
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
        undoMenuItems
    }

    /// Seçili öğeler için toplu eylemler — hem satır hem grup menüsünde.
    @ViewBuilder
    private var undoMenuItems: some View {
        let selectedUndoable = (shell.plastic.changes[repoPath] ?? [])
            .filter { $0.status != .untracked && shell.plastic.isSelected(repoPath, path: $0.path) }
            .count
        if selectedUndoable > 0 {
            Button("Undo Changes of \(selectedUndoable) Selected Item\(selectedUndoable == 1 ? "" : "s")", role: .destructive) {
                Task { await shell.plastic.undoSelected(repoPath) }
            }
        }
        Button("Undo Unchanged Checkouts") {
            Task { await shell.plastic.undoUnchanged(repoPath) }
        }
        .help("Release checked-out files whose content did not change (whole workspace)")
    }

    /// Dosya satırı girintisi: grup chevron'u (md + lg) + iki küçük adım —
    /// kutu grubun kutusundan belirgin içeride durur ama yol alanı korunur.
    private static let fileRowIndent = Theme.Spacing.md + Theme.Spacing.lg + Theme.Spacing.sm + Theme.Spacing.xs
    /// Kılavuz çizgi chevron'un ortasından iner.
    private static let indentGuideOffset = Theme.Spacing.md + Theme.Spacing.lg / 2

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
