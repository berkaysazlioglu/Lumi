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
        ImagePane(
            title: title,
            data: data,
            missing: preview.isTooLarge ? "(too large)" : missing,
            accent: accent
        )
    }

    private func placeholder(_ text: String) -> some View {
        ImagePlaceholder(text: text)
    }
}

/// Tek görsel paneli: decode body'de değil, veri değişince BİR KEZ yapılır
/// (`.task(id:)` + `@State`, HighlightedCodeView kalıbı).
private struct ImagePane: View {
    let title: String
    let data: Data?
    /// Veri hiç yoksa gösterilecek metin (eklendi/silindi/çok büyük).
    let missing: String
    let accent: Color

    @State private var image: NSImage?
    @State private var caption = ""
    @State private var didDecode = false

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(0.5)
                .foregroundStyle(accent)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: data) {
            didDecode = false
            image = nil
            caption = ""
            guard let data else {
                didDecode = true
                return
            }
            let decoded = NSImage(data: data)
            image = decoded
            caption = decoded.map { ImagePreviewCaption.make(image: $0, byteCount: data.count) } ?? ""
            didDecode = true
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            // bgDeep zemin: saydam PNG'lerin sınırları koyu temada görünsün
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(6)
                .background(Theme.bgDeep)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(caption)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        } else if !didDecode {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if data != nil {
            // Bayt var ama AppKit çözemedi (bozuk/desteklenmeyen kodek)
            ImagePlaceholder(text: "(unsupported image format)")
        } else {
            ImagePlaceholder(text: missing)
        }
    }
}

private struct ImagePlaceholder: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Theme.textMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Görsel altyazısı: "1024×512 · 84 KB" — saf biçimlendirme (test edilir).
enum ImagePreviewCaption {
    static func make(pixelWidth: Int, pixelHeight: Int, byteCount: Int) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
        return "\(pixelWidth)×\(pixelHeight) · \(size)"
    }

    /// KRİTİK: piksel boyutu representation'dan okunur — `NSImage.size` DPI'a
    /// göre ölçekli gelir, retina asset'lerde yanıltıcı olur.
    static func make(image: NSImage, byteCount: Int) -> String {
        let representation = image.representations.first
        return make(
            pixelWidth: representation?.pixelsWide ?? Int(image.size.width),
            pixelHeight: representation?.pixelsHigh ?? Int(image.size.height),
            byteCount: byteCount
        )
    }
}
