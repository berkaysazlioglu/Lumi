import Foundation

/// FileViewer'ın bir dosyayı nasıl sunacağını belirleyen uzantı sınıflaması
/// (karar 21): `markdown` → render'lı görünüm/diff, `image` → görsel önizleme,
/// `binary` → metin olarak OKUNMAZ ("önizleme yok" yer tutucusu; video dosyası
/// metin diye açılınca çöken FileViewer düzeltmesi), `text` → mevcut
/// syntax-highlight / side-by-side diff yolu.
///
/// Uzantı-tabanlı ve saf: içerik sniffing yapılmaz (git binary'yi kendisi
/// işaretler, `UnifiedDiff.isBinary`). SVG bilinçli olarak `text`'tir — XML
/// olarak anlamlı diff'lenir.
public enum FilePreviewKind: String, Sendable, Equatable, CaseIterable {
    case markdown
    case image
    case binary
    case text

    private static let markdownExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mdx",
    ]

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tif", "tiff", "webp", "heic", "heif", "ico",
    ]

    /// Uzantıdan kesin bilinen binary aileler: video, ses, arşiv, font,
    /// belge/ofis, derlenmiş çıktı, disk imajı, veritabanı, ML modeli.
    /// Uzantısı yanıltan dosyalar için ikinci savunma hattı servis tarafındaki
    /// içerik sniff'idir (`GitService.readFile`).
    private static let binaryExtensions: Set<String> = [
        // video
        "mp4", "m4v", "mov", "avi", "mkv", "webm", "wmv", "flv", "mpg", "mpeg", "3gp",
        // ses
        "mp3", "m4a", "aac", "wav", "flac", "ogg", "oga", "opus", "wma", "aiff", "aif", "caf",
        // arşiv / paket
        "zip", "gz", "tgz", "bz2", "xz", "7z", "rar", "tar", "jar", "war", "aar", "apk", "ipa",
        "dmg", "iso", "pkg", "xip", "deb", "rpm",
        // font
        "ttf", "otf", "woff", "woff2", "ttc", "eot",
        // belge / ofis
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "key", "numbers", "pages", "psd",
        "ai", "sketch", "fig",
        // derlenmiş / ikili çıktı
        "o", "a", "so", "dylib", "dll", "exe", "bin", "class", "pyc", "pyo", "wasm", "swiftmodule",
        "swiftdoc", "nib", "car", "mlmodel", "mlmodelc", "onnx", "pt", "pth", "safetensors",
        "ckpt", "tflite", "pb", "h5", "npy", "npz", "parquet",
        // veritabanı / diğer
        "sqlite", "sqlite3", "db", "realm", "mdb", "plist_bin", "dat",
    ]

    public static func of(path: String) -> FilePreviewKind {
        let fileExtension = (path as NSString).pathExtension.lowercased()
        if markdownExtensions.contains(fileExtension) { return .markdown }
        if imageExtensions.contains(fileExtension) { return .image }
        if binaryExtensions.contains(fileExtension) { return .binary }
        return .text
    }
}
