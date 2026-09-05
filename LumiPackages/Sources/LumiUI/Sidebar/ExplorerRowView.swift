import LumiKit
import SwiftUI

/// Explorer'ın tek dosya/klasör satırı.
///
/// `ExplorerView`'dan ayrıldı: satırın kendi hover'ı, sürüklemesi ve altı
/// öğelik bağlam menüsü var; liste mantığıyla (arama, seçim, klavye) aynı
/// dosyada durunca ikisi de okunmaz oluyordu.
///
/// Renk kuralı: İKON türü söyler (`Theme.fileColor`), İSİM git durumunu söyler
/// (`Theme.fileChangeColor`). Önce ikisi de aynı rengi paylaşıyordu, bu yüzden
/// bir dosyanın türü mü yoksa değiştiği mi vurgulanıyor ayırt edilemiyordu.
struct ExplorerRowView: View {
    let repoPath: String
    let row: FileTreeRows.Row
    let isSelected: Bool
    let status: FileChangeStatus?
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onPresent: () -> Void
    let onEdit: (_ kind: ExplorerEditPrompt.Kind, _ path: String, _ name: String) -> Void
    @Shell private var shell

    private var kind: FileKind {
        FileKind.classify(name: row.name, isFolder: row.type == .folder, isExpanded: row.isExpanded)
    }

    private var nameColor: Color {
        if let status { return Theme.fileChangeColor(for: status) }
        return row.isIgnored ? Theme.textMuted : Theme.textPrimary
    }

    var body: some View {
        HoverReader { hovering in
            HStack(spacing: Theme.Spacing.sm) {
                chevron
                FileKindIcon(kind: kind)
                Text(row.name)
                    .font(Theme.Typography.ui(.body))
                    .italic(row.isIgnored)
                    .foregroundStyle(nameColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                badge
            }
            .padding(.leading, CGFloat(row.level) * Theme.Spacing.xl + Theme.Spacing.md)
            .padding(.trailing, Theme.Spacing.md)
            .frame(height: Theme.Row.compact)
            .background(background(hovering: hovering))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onSelect(); if row.type == .file { onPresent() } }
            .onTapGesture { onSelect(); if row.type == .folder { onOpen() } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onOpen() }
            .help(row.path)
            .onDrag { NSItemProvider(object: fileURL as NSURL) }
            .contextMenu { menu }
        }
    }

    @ViewBuilder
    private var chevron: some View {
        if row.type == .folder {
            Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                .font(Theme.Typography.ui(.caption))
                .foregroundStyle(Theme.textMuted)
                .frame(width: Theme.Spacing.lg)
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(width: Theme.Spacing.lg, height: Theme.Spacing.xxs)
        }
    }

    @ViewBuilder
    private var badge: some View {
        if let status {
            Text(status.badgeText)
                .font(Theme.Typography.ui(.caption, weight: .medium))
                .foregroundStyle(Theme.fileChangeColor(for: status))
        } else if row.isIgnored {
            Text("I")
                .font(Theme.Typography.ui(.caption))
                .foregroundStyle(Theme.textMuted)
        }
    }

    @ViewBuilder
    private var menu: some View {
        if row.type == .file {
            Button("Open") { onPresent() }
            if status != nil { Button("Open Changes") { shell.presentDiff(row.path) } }
        }
        if row.type == .folder {
            Button("New File…") { onEdit(.newFile, row.path, "") }
            Button("New Folder…") { onEdit(.newFolder, row.path, "") }
        }
        Button("Rename…") { onEdit(.rename, row.path, row.name) }
        Button("Copy Path") { copy(fileURL.path) }
        Button("Copy Relative Path") { copy(row.path) }
        Button("Reveal in Finder") { shell.reveal(row.path) }
        Divider()
        Button("Move to Trash", role: .destructive) { shell.trash(row.path) }
    }

    private var fileURL: URL {
        URL(fileURLWithPath: repoPath).appendingPathComponent(row.path)
    }

    private func background(hovering: Bool) -> Color {
        if isSelected { return Theme.accentPrimary.opacity(0.15) }
        return hovering ? Theme.bgElevated : .clear
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
