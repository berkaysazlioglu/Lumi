import Foundation

/// FileViewer'ın bir dosyayı nasıl sunacağını belirleyen uzantı sınıflaması
/// (karar 21): `markdown` → render'lı görünüm/diff, `image` → görsel önizleme,
/// `text` → mevcut syntax-highlight / side-by-side diff yolu.
///
/// Uzantı-tabanlı ve saf: içerik sniffing yapılmaz (git binary'yi kendisi
/// işaretler, `UnifiedDiff.isBinary`). SVG bilinçli olarak `text`'tir — XML
/// olarak anlamlı diff'lenir.
public enum FilePreviewKind: String, Sendable, Equatable, CaseIterable {
    case markdown
    case image
    case text

    private static let markdownExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mdx",
    ]

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tif", "tiff", "webp", "heic", "heif", "ico",
    ]

    public static func of(path: String) -> FilePreviewKind {
        let fileExtension = (path as NSString).pathExtension.lowercased()
        if markdownExtensions.contains(fileExtension) { return .markdown }
        if imageExtensions.contains(fileExtension) { return .image }
        return .text
    }
}
