import AppKit
import ImageIO
import LumiKit
import LumiState
import SwiftUI

/// Detaydaki görsel şeridi (Tasks planı: "Görseller").
///
/// Optimizasyon: kart yalnız sayıyı gösterir, hiçbir şey indirmez. Şerit
/// detay açılınca görünür hücreler için önizlemeyi (`thumbnailURL`, yoksa
/// asıl görsel) store'dan yerel dosya olarak ister — store disk önbelleğine
/// gider — ve hücre boyutuna küçültüp bellekte tutar. Tam boyut yalnız
/// tıklanınca Lumi viewer'ında açılır.
struct TaskImageStrip: View {
    let store: TasksStore
    let entry: TaskEntry

    @Shell private var shell

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.md) {
                ForEach(entry.item.images) { image in
                    TaskImageThumbnail(store: store, source: entry.source, taskID: entry.item.id, image: image) {
                        open(image)
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.xxs)
        }
    }

    private func open(_ image: TaskImage) {
        Task {
            guard let file = await store.imageFile(for: image.url, in: entry.source, task: entry.item.id) else {
                shell.toasts.show(.error, title: "Couldn't load \(image.displayName)", message: "See Errors for details.")
                return
            }
            await shell.fileViewer.presentView(
                repoPath: file.deletingLastPathComponent().path,
                filePath: file.lastPathComponent
            )
        }
    }
}

private struct TaskImageThumbnail: View {
    let store: TasksStore
    let source: TaskSourceID
    let taskID: String
    let image: TaskImage
    let onOpen: () -> Void

    @State private var thumbnail: NSImage?
    @State private var didFail = false

    static var width: CGFloat { Theme.scaled(112) }
    static var height: CGFloat { Theme.scaled(80) }

    var body: some View {
        Button(action: onOpen) {
            ZStack {
                Theme.bgDeep
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if didFail {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(Theme.Typography.ui(.title))
                        .foregroundStyle(Theme.textMuted)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: Self.width, height: Self.height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.border, lineWidth: Theme.Stroke.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(image.displayName + (image.width.map { w in image.height.map { " · \(w)×\($0)" } ?? "" } ?? ""))
        .accessibilityLabel("Image \(image.displayName)")
        .task(id: image.url) { await load() }
    }

    private func load() async {
        let url = image.thumbnailURL ?? image.url
        if let cached = TaskThumbnailCache.shared.object(forKey: url as NSURL) {
            thumbnail = cached
            return
        }
        guard let file = await store.imageFile(for: url, in: source, task: taskID) else {
            didFail = true
            return
        }
        // Retina'da hücrenin iki katı yeter; büyük görsel asla tam çözülmez.
        let maxPixel = Int(max(Self.width, Self.height) * 2)
        let made = await Task.detached(priority: .utility) { TaskThumbnailCache.downsample(file, maxPixel: maxPixel) }.value
        guard let made else {
            didFail = true
            return
        }
        TaskThumbnailCache.shared.setObject(made, forKey: url as NSURL)
        thumbnail = made
    }
}

/// Küçültülmüş önizlemelerin bellek önbelleği (oturumluk; disk önbelleği
/// servis katmanındadır).
enum TaskThumbnailCache {
    nonisolated(unsafe) static let shared: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 200
        return cache
    }()

    /// ImageIO ile doğrudan küçük boyutta çözer — tam görsel belleğe alınmaz.
    static func downsample(_ file: URL, maxPixel: Int) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(file as CFURL, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
