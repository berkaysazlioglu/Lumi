import LumiKit
import LumiState
import SwiftUI

/// Source Control sekmesi (karar 39/40/41).
///
/// Başlık (`SourceControlHeader`) → Changes | History anahtarı → gövde.
/// Changes: mesaj kutusu, bölünmüş Commit butonu (sağdaki ok seçim
/// eylemlerini açar), katlanabilir CHANGES listesi. History: commit graph'ı.
struct SourceControlView: View {
    enum Section: Hashable, CaseIterable {
        case changes
        case history
    }

    let repoPath: String
    @Shell private var shell
    @State private var section: Section = .changes
    @State private var changesCollapsed = false
    @State private var showsCommitMenu = false

    private var changes: [GitFileChange] { shell.git.changes[repoPath] ?? [] }
    private var selectedCount: Int { shell.git.selectedFiles[repoPath]?.count ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            SourceControlHeader(repoPath: repoPath)
            SegmentedModeSwitch(
                options: Section.allCases,
                selection: $section,
                title: { $0 == .changes ? "Changes" : "History" },
                accessibilityLabel: "Source control section"
            )
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.md)
            switch section {
            case .history: CommitGraphView(repoPath: repoPath)
            case .changes: changesBody
            }
        }
        .onChange(of: repoPath) { section = .changes }
    }

    // MARK: - Changes

    private var changesBody: some View {
        VStack(spacing: 0) {
            composer
                .padding(.horizontal, Theme.Spacing.md)
            SectionHeader(
                title: "Changes",
                count: changes.isEmpty ? nil : .warning(changes.count),
                disclosure: .leading,
                isExpanded: !changesCollapsed,
                contentPadding: Theme.Spacing.md,
                onToggle: { changesCollapsed.toggle() }
            ) {
                if !changes.isEmpty {
                    Button(selectedCount == changes.count ? "Deselect All" : "Select All") {
                        shell.git.toggleSelectAll(repoPath)
                    }
                    .buttonStyle(.plain)
                    .font(Theme.Typography.ui(.caption))
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            if !changesCollapsed {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if changes.isEmpty {
                            EmptyStatePlaceholder("No changes — working tree clean", density: .inline)
                        }
                        ForEach(changes) { change in changeRow(change) }
                    }
                }
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: Theme.Spacing.md) {
            CommitMessageField(
                placeholder: "Message",
                text: Binding(
                    get: { shell.git.commitMessage(for: repoPath) },
                    set: { shell.git.setCommitMessage($0, for: repoPath) }
                ),
                isGenerating: shell.commitAssistant.isGenerating(repoPath),
                canGenerate: selectedCount > 0,
                onGenerate: {
                    let path = repoPath
                    Task { await shell.generateGitCommitMessage(path) }
                }
            )
            commitButton
        }
        .padding(.bottom, Theme.Spacing.sm)
    }

    /// Bölünmüş buton (Orca "Stage All ▾"): sol yarı commit, sağ ok seçim
    /// eylemleri. İki yarı aynı zemini paylaşır, aralarında hairline ayraç var.
    /// Yükseklik sabittir (`Row.control`); esnek `maxHeight` bırakılırsa buton
    /// gövdenin boş alanını yutup devasa görünür.
    private var commitButton: some View {
        let canCommit = shell.git.canCommit(repoPath)
        return HStack(spacing: 0) {
            Button {
                Task { await shell.git.commit(repoPath) }
            } label: {
                Label(
                    shell.git.isCommitting ? "Committing…" : "Commit (\(selectedCount))",
                    systemImage: shell.git.isCommitting ? "hourglass" : "checkmark"
                )
                .font(Theme.Typography.ui(.body, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Row.control)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canCommit)
            Rectangle().fill(Theme.border).frame(width: Theme.Stroke.hairline, height: Theme.Row.control)
            Button { showsCommitMenu.toggle() } label: {
                Image(systemName: "chevron.down")
                    .font(Theme.Typography.ui(.caption, weight: .bold))
                    .frame(width: Theme.Spacing.xxxl, height: Theme.Row.control)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("More commit actions")
            .accessibilityLabel("More commit actions")
            .popover(isPresented: $showsCommitMenu, arrowEdge: .bottom) {
                PopoverMenu(items: commitMenuItems, dismiss: { showsCommitMenu = false })
            }
        }
        .foregroundStyle(canCommit ? Theme.textPrimary : Theme.textMuted)
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
        )
    }

    private var commitMenuItems: [PopoverMenu.Item] {
        [
            .action("Select All", icon: "checkmark.square", isEnabled: selectedCount < changes.count) {
                if selectedCount < changes.count { shell.git.toggleSelectAll(repoPath) }
            },
            .action("Deselect All", icon: "square", isEnabled: selectedCount > 0) {
                if selectedCount > 0 { shell.git.toggleSelectAll(repoPath) }
            },
            .divider,
            .action("Clear Message", icon: "eraser", isEnabled: !shell.git.commitMessage(for: repoPath).isEmpty) {
                shell.git.setCommitMessage("", for: repoPath)
            },
        ]
    }

    private func changeRow(_ change: GitFileChange) -> some View {
        let color = Theme.fileChangeColor(for: change.status)
        let name = (change.path as NSString).lastPathComponent
        return HoverReader { hovering in
            HStack(spacing: Theme.Spacing.sm) {
                Button { shell.git.toggleFile(repoPath, path: change.path) } label: {
                    Image(systemName: shell.git.isSelected(repoPath, path: change.path) ? "checkmark.square.fill" : "square")
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Include \(change.path) in commit")
                .accessibilityLabel("Include \(change.path) in commit")
                Button { shell.presentDiff(change.path) } label: {
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
                    Button("Open Changes") { shell.presentDiff(change.path) }
                    if change.status != .deleted { Button("Open File") { shell.presentFile(change.path) } }
                    Button("Reveal in Finder") { shell.reveal(change.path) }
                }
            }
            .font(Theme.Typography.ui(.body))
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Row.compact)
            .background(hovering ? Theme.bgElevated : .clear)
        }
    }
}
