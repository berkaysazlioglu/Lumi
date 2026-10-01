import LumiKit
import SwiftUI

/// Açılmış commit satırının gövdesi (Orca `GitHistoryCommitFiles` portu):
/// yazar · tarih, dosya listesi (tıklayınca o dosyanın diff'iyle commit açılır)
/// ve "Open all changes together".
///
/// Solda satırın çıkış lane'leri kesintisiz iner; graph açılımla kopmaz.
struct GitCommitFilesView: View {
    let row: CommitGraphRow
    let laneCount: Int
    let files: Loadable<[CommitFile]>?
    let onOpenFile: (String) -> Void
    let onOpenAll: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            CommitGraphContinuationCanvas(lanes: row.outputLanes, laneCount: laneCount)
            VStack(alignment: .leading, spacing: 0) {
                meta
                filesBody
            }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: Theme.Stroke.hairline)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var meta: some View {
        Text("\(row.commit.author) · \(RelativeTimeFormatter.label(row.commit.date))")
            .font(Theme.Typography.ui(.caption))
            .foregroundStyle(Theme.textMuted)
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Row.compact)
    }

    @ViewBuilder
    private var filesBody: some View {
        switch files {
        case .loaded(let list) where list.isEmpty:
            note("No file changes in this commit")
        case .loaded(let list):
            ForEach(list) { file in fileRow(file) }
            openAllRow
        case .failed(let message):
            note(message, color: Theme.error)
        case .loading, nil:
            note("Loading files…")
        }
    }

    private func fileRow(_ file: CommitFile) -> some View {
        let color = Theme.fileChangeColor(for: file.status)
        let name = (file.path as NSString).lastPathComponent
        let directory = (file.path as NSString).deletingLastPathComponent
        return HoverReader { hovering in
            Button { onOpenFile(file.path) } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    FileKindIcon(kind: FileKind.classify(name: name, isFolder: false, isExpanded: false))
                    Text(name).foregroundStyle(color).lineLimit(1)
                    Text(directory)
                        .font(Theme.Typography.ui(.caption))
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer(minLength: 0)
                    Text(file.status.badgeText)
                        .font(Theme.Typography.mono(.caption, weight: .medium))
                        .foregroundStyle(color)
                }
                .font(Theme.Typography.ui(.body))
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: Theme.Row.compact)
                .background(hovering ? Theme.bgElevated : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(file.path)
        }
    }

    private var openAllRow: some View {
        Button(action: onOpenAll) {
            Label("Open all changes together", systemImage: "arrow.up.right")
                .font(Theme.Typography.ui(.caption))
                .padding(.horizontal, Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Theme.Row.compact)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverButtonStyle())
    }

    private func note(_ text: String, color: Color = Theme.textMuted) -> some View {
        Text(text)
            .font(Theme.Typography.ui(.caption))
            .foregroundStyle(color)
            .lineLimit(2)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: Theme.Row.compact)
    }
}
