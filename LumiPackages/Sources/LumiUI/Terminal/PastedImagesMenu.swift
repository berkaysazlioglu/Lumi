import AppKit
import LumiKit
import LumiState
import SwiftUI

/// Kart header'ındaki görsel düğmesi (karar 139): Claude terminalinin bu
/// oturumda prompt'a yapıştırılan görsellerini listeleyen popover'ı açar.
struct PastedImagesButton: View {
    let meta: TerminalMeta
    @State private var isOpen = false

    var body: some View {
        IconButton(
            systemName: "photo.on.rectangle",
            label: "Pasted images",
            size: .caption,
            isActive: isOpen
        ) { isOpen.toggle() }
            .help("Pasted images")
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                PastedImagesMenu(meta: meta, dismiss: { isOpen = false })
            }
    }
}

/// Görseller alt alta: küçük önizleme + `Image #N`, sağda Lumi viewer'ında aç /
/// Finder'da göster ikon butonları. Satırın geri kalanına tık `[Image #N]`
/// referansını terminalin prompt'una yapıştırır (göndermez).
struct PastedImagesMenu: View {
    @Shell private var shell
    let meta: TerminalMeta
    let dismiss: () -> Void
    @State private var images: [ClaudePastedImage]?

    static var width: CGFloat { Theme.scaled(280) }
    private static var maxListHeight: CGFloat { Theme.scaled(420) }

    var body: some View {
        Group {
            if let images, !images.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                        ForEach(images) { row($0) }
                    }
                }
                .frame(height: min(CGFloat(images.count) * PastedImageRowMetrics.height, Self.maxListHeight))
            } else {
                Text(images == nil ? "Loading…" : "No images pasted in this session")
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(width: Self.width)
        .background(Theme.bgElevated)
        .task(id: meta.claudeSessionID) { images = await shell.pastedImages.images(for: meta) }
    }

    private func row(_ image: ClaudePastedImage) -> some View {
        PastedImageRow(image: image) {
            dismiss()
            shell.mentionPastedImage(image, in: meta)
        } trailing: {
            IconButton(systemName: "doc.text.magnifyingglass", label: "Open in Lumi Viewer", side: Theme.scaled(24)) {
                dismiss()
                shell.openPastedImage(image, revealInFinder: false)
            }
            IconButton(systemName: "folder", label: "Reveal in Finder", side: Theme.scaled(24)) {
                dismiss()
                shell.openPastedImage(image, revealInFinder: true)
            }
        }
    }
}

private enum PastedImageRowMetrics {
    static var height: CGFloat { Theme.scaled(48) }
    static var thumbnailSide: CGFloat { Theme.scaled(40) }
}

/// Önizleme + ad satırı; satırın kendisi `action`, sağda çağıranın butonları.
private struct PastedImageRow<Trailing: View>: View {
    let image: ClaudePastedImage
    let action: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    @State private var thumbnail: NSImage?

    var body: some View {
        HoverReader { isHovering in
            HStack(spacing: Theme.Spacing.sm) {
                Button(action: action) { label }
                    .buttonStyle(.plain)
                trailing().fixedSize()
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(height: PastedImageRowMetrics.height)
            .background(isHovering ? Theme.bgDeep : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .help("Insert \(image.reference) into the prompt")
        .task(id: image.path) { await loadThumbnail() }
    }

    private var label: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Theme.bgDeep
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo")
                        .font(Theme.Typography.ui(.label))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .frame(width: PastedImageRowMetrics.thumbnailSide, height: PastedImageRowMetrics.thumbnailSide)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                Text("Image #\(image.number)")
                    .font(Theme.Typography.mono(.body, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(image.fileName)
                    .font(Theme.Typography.mono(.caption))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func loadThumbnail() async {
        let file = URL(fileURLWithPath: image.path)
        // Retina'da kutunun iki katı yeter; tam görsel çözülmez.
        let maxPixel = Int(PastedImageRowMetrics.thumbnailSide * 2)
        thumbnail = await Task.detached(priority: .utility) {
            TaskThumbnailCache.downsample(file, maxPixel: maxPixel)
        }.value
    }
}
