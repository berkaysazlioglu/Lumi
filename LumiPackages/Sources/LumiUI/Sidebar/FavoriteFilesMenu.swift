import LumiKit
import LumiState
import SwiftUI

/// Top bar `Files` listesinin içeriği (karar 107): favoriler alt alta, her
/// satırda iki ikon buton — Lumi viewer'ında aç / Finder'da göster. Satırın
/// kendisine tıklamak da viewer'da açar.
///
/// Silinen dosya `missing` çizilir (soluk ad + uyarı ikonu) ve açma
/// butonlarının yerini `Relink…` / `Remove` alır. Taşınan dosya yeni yerinden
/// açılır; projenin kendi kökünde açıldıysa yeni yol kalıcı yazılır.
struct FavoriteFilesMenu: View {
    @Shell private var shell
    let projectPath: String
    let checkoutPath: String
    /// Diski silinmiş workspace: açma eylemleri kapalı, yönetim açık.
    let isCheckoutMissing: Bool
    let dismiss: () -> Void

    static var width: CGFloat { Theme.scaled(304) }
    private static var maxListHeight: CGFloat { Theme.scaled(420) }

    var body: some View {
        let entries = shell.favoriteFiles.entries(
            projectPath: projectPath, checkoutPath: checkoutPath, tree: shell.repos.fileTrees[checkoutPath]
        )
        VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
            if entries.isEmpty {
                Text("No favorite files yet")
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                        ForEach(entries) { row($0) }
                    }
                }
                .frame(height: min(CGFloat(entries.count) * FavoriteFileRowMetrics.height, Self.maxListHeight))
            }
            Rectangle()
                .fill(Theme.border)
                .frame(height: Theme.Stroke.hairline)
                .padding(.vertical, Theme.Spacing.xs)
            Button { openManager() } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "star")
                        .font(Theme.Typography.ui(.label))
                        .frame(width: Theme.Row.iconColumn)
                        .accessibilityHidden(true)
                    Text(entries.isEmpty ? "Add Files…" : "Manage Favorites…").lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(Theme.Typography.ui(.body))
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: Theme.Row.compact + Theme.Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(HoverButtonStyle(
                foreground: Theme.textPrimary, hoverForeground: Theme.textPrimary,
                background: .clear, hoverBackground: Theme.bgDeep, cornerRadius: Theme.Radius.sm
            ))
        }
        .padding(Theme.Spacing.sm)
        .frame(width: Self.width)
        .background(Theme.bgElevated)
        .task(id: entries) {
            // Taşınma yalnız projenin kendi kökünde kalıcıdır (FavoriteFileStore).
            guard checkoutPath == projectPath else { return }
            await shell.favoriteFiles.persistMoves(entries)
        }
    }

    @ViewBuilder
    private func row(_ entry: FavoriteFileEntry) -> some View {
        if let path = entry.resolvedPath {
            FavoriteFileRow(
                path: path,
                detail: movedDetail(entry),
                isMissing: false,
                action: isCheckoutMissing ? nil : { open(path, reveal: false) }
            ) {
                IconButton(systemName: "doc.text.magnifyingglass", label: "Open in Lumi Viewer", side: Theme.scaled(24)) {
                    open(path, reveal: false)
                }
                .disabled(isCheckoutMissing)
                IconButton(systemName: "folder", label: "Reveal in Finder", side: Theme.scaled(24)) {
                    open(path, reveal: true)
                }
                .disabled(isCheckoutMissing)
            }
        } else {
            FavoriteFileRow(
                path: entry.favorite.relativePath,
                detail: "Not found — moved or deleted",
                isMissing: true,
                action: nil
            ) {
                IconButton(systemName: "magnifyingglass", label: "Relink…", side: Theme.scaled(24)) {
                    openManager(relinking: entry.favorite)
                }
                IconButton(systemName: "trash", label: "Remove from Favorites", side: Theme.scaled(24), role: .destructive) {
                    Task { await shell.favoriteFiles.remove(id: entry.favorite.id) }
                }
            }
        }
    }

    private func movedDetail(_ entry: FavoriteFileEntry) -> String? {
        guard case .moved = entry.location else { return nil }
        return "Moved from \(entry.favorite.relativePath)"
    }

    private func open(_ path: String, reveal: Bool) {
        dismiss()
        shell.openFavoriteFile(path, in: checkoutPath, revealInFinder: reveal)
    }

    private func openManager(relinking favorite: ProjectFavoriteFile? = nil) {
        dismiss()
        shell.dialogs.present(.favoriteFiles(FavoriteFilesDialogState(
            projectPath: projectPath,
            checkoutPath: checkoutPath,
            relinkID: favorite?.id,
            initialQuery: favorite?.name ?? ""
        )))
    }
}

enum FavoriteFileRowMetrics {
    /// İki satırlık (ad + klasör) sabit satır yüksekliği.
    static var height: CGFloat { Theme.scaled(38) }
}

/// Favori/arama satırı: dosya ikonu + ad, altında soluk klasör yolu (ya da
/// `detail`), sağda çağıranın butonları. Menü ve modal aynı satırı çizer.
struct FavoriteFileRow<Trailing: View>: View {
    let path: String
    /// Klasör yolunun yerine gösterilecek not (taşındı / bulunamadı).
    var detail: String?
    let isMissing: Bool
    var isSelected = false
    /// `nil` → satır tıklanamaz (yalnız butonlar).
    let action: (() -> Void)?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HoverReader { isHovering in
            HStack(spacing: Theme.Spacing.sm) {
                Button { action?() } label: { label }
                    .buttonStyle(.plain)
                    .disabled(action == nil)
                // Butonlar sıkışmaz; dar listede ad `…` ile kısalır.
                trailing().fixedSize()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: FavoriteFileRowMetrics.height)
            .background((isHovering || isSelected) ? Theme.bgDeep : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .help(path)
    }

    private var label: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if isMissing {
                Image(systemName: "exclamationmark.triangle")
                    .font(Theme.Typography.ui(.label))
                    .foregroundStyle(Theme.warning)
                    .frame(width: Theme.Row.iconColumn)
                    .accessibilityLabel("Missing")
            } else {
                FileKindIcon(kind: FileKind.classify(name: FavoriteFilePath.name(of: path), isFolder: false, isExpanded: false))
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                Text(FavoriteFilePath.name(of: path))
                    .font(Theme.Typography.mono(.body, weight: .medium))
                    .foregroundStyle(isMissing ? Theme.textMuted : Theme.textPrimary)
                    .strikethrough(isMissing)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(Theme.Typography.mono(.caption))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        if let detail { return detail }
        let directory = FavoriteFilePath.directory(of: path)
        return directory.isEmpty ? "/" : directory
    }
}
