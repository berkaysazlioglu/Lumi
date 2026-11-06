import AppKit
import SwiftTerm
import UniformTypeIdentifiers

/// Uzak aynanın terminal view'ı: yapıştırma görsel içeriyorsa metin yerine görseli
/// hub'a yollar (karar 143 ek). Görsel, hub'da diske yazılıp yolu terminale yazılır.
final class RemoteMirrorTerminalView: TerminalView {
    /// Panodaki görselin ham baytları (kodlama çağıranda, main dışında yapılır).
    var onPasteImage: ((Data) -> Void)?

    override func paste(_ sender: Any) {
        if pasteImageIfAvailable() { return }
        super.paste(sender)
    }

    /// ⌘V ve Claude'un görsel tuşu ⌃V: yerel panoda görsel varsa gönderir. Aksi halde
    /// `false` — ⌃V hub'a gider (hub'ın kendi panosu).
    func pasteImageIfAvailable() -> Bool {
        guard let onPasteImage else { return false }
        let images = Self.imageData(from: .general)
        guard !images.isEmpty else { return false }
        images.forEach(onPasteImage)
        return true
    }

    static let maxFilesPerPaste = 5

    /// Görsel dosyaları (Finder'dan kopyalanan) ya da metinsiz görsel verisi (ekran görüntüsü).
    /// Metin varsa metin yapıştırılır — Office gibi uygulamalar metne görsel temsil de ekler.
    static func imageData(from pasteboard: NSPasteboard) -> [Data] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let imageFiles = urls.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
        if !urls.isEmpty {
            return imageFiles.prefix(maxFilesPerPaste).compactMap { try? Data(contentsOf: $0) }
        }
        if pasteboard.string(forType: .string) != nil { return [] }
        let types: [NSPasteboard.PasteboardType] = [.png, .tiff, .init(UTType.jpeg.identifier), .init(UTType.heic.identifier)]
        for type in types {
            if let data = pasteboard.data(forType: type) { return [data] }
        }
        return []
    }
}
