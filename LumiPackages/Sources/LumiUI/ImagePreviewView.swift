import AppKit
import LumiKit
import SwiftUI

/// Görsel dosya önizlemesi (karar 21). Diff/commit-diff modunda "before → after"
/// yan yana (eksik taraf = eklenen/silinen dosya), view modunda tek görsel.
/// Metin diff'i yerine bunu göstermek, git'in binary olarak işaretlediği
/// dosyalarda "(binary file)" placeholder'ının yerini alır.
struct ImagePreviewView: View {
    let preview: ImagePreview
    /// view modunda karşılaştırma yok — yalnız güncel görsel.
    let showsComparison: Bool

    var body: some View {
        Group {
            if !preview.hasContent {
                placeholder(
                    preview.isTooLarge ? "(image too large to preview)" : "(preview unavailable)"
                )
            } else if showsComparison {
                HStack(spacing: 0) {
                    pane(title: "BEFORE", data: preview.before, missing: "(added)", accent: Theme.error)
                    Rectangle().fill(Theme.border).frame(width: 1)
                    pane(title: "AFTER", data: preview.after, missing: "(deleted)", accent: Theme.success)
                }
            } else {
                pane(
                    title: (preview.filePath as NSString).lastPathComponent.uppercased(),
                    data: preview.after ?? preview.before,
                    missing: "(unavailable)",
                    accent: Theme.accentPrimary
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgSurface)
    }

    private func pane(title: String, data: Data?, missing: String, accent: Color) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(0.5)
                .foregroundStyle(accent)
            if let data, let image = NSImage(data: data) {
                // bgDeep zemin: saydam PNG'lerin sınırları koyu temada görünsün
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(6)
                    .background(Theme.bgDeep)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(caption(image: image, byteCount: data.count))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            } else if data != nil {
                // Bayt var ama AppKit çözemedi (bozuk/desteklenmeyen kodek)
                placeholder("(unsupported image format)")
            } else {
                placeholder(preview.isTooLarge ? "(too large)" : missing)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "1024×512 · 84 KB" — piksel boyutu representation'dan (NSImage.size DPI'a
    /// göre ölçekli gelir, retina asset'lerde yanıltıcı olur).
    private func caption(image: NSImage, byteCount: Int) -> String {
        let representation = image.representations.first
        let width = representation?.pixelsWide ?? Int(image.size.width)
        let height = representation?.pixelsHigh ?? Int(image.size.height)
        let size = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
        return "\(width)×\(height) · \(size)"
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Theme.textMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
