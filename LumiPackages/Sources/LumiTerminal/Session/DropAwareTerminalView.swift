import AppKit
import SwiftTerm

/// Dosya sürükle-bırak destekli terminal view'ı (spec/20 §drag-drop).
/// SwiftTerm drop'u kendisi işlemez; Electron'daki app-seviyesi davranışın
/// karşılığıdır: bırakılan dosyaların path'i terminale girdi olarak yazılır.
final class DropAwareTerminalView: TerminalView {
    /// Main thread'de çağrılır; path'ler quote'lanmamış ham halleriyle gelir.
    var onFileDrop: (([String]) -> Void)?

    override init(frame: CGRect, font: NSFont?) {
        super.init(frame: frame, font: font)
        configureLumiDefaults()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLumiDefaults()
    }

    private func configureLumiDefaults() {
        registerForDraggedTypes([.fileURL])
        // macOS konvansiyonu (Terminal.app): Option meta DEĞİLDİR — Option'lı
        // tuşlar birleşik karakter üretir (TR klavyede [ ] { } vb. Option ister).
        // SwiftTerm default'u true'dur ve bu karakterleri ESC+harf'e çevirirdi.
        optionAsMetaKey = false
        TerminalTheme.apply(to: self)
        hideScroller()
    }

    /// SwiftTerm her zaman bir NSScroller subview'i ekler ve gizleme API'si sunmaz.
    /// v1 paritesi: kaydırma çubuğu görünmez (fare tekeriyle scroll çalışmaya devam
    /// eder — scroller yalnız görsel göstergedir). isHidden kalıcıdır; SwiftTerm
    /// hiçbir yerde tekrar göstermez. viewDidMoveToWindow'da da garanti edilir.
    private func hideScroller() {
        for case let scroller as NSScroller in subviews {
            scroller.isHidden = true
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hideScroller()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onFileDrop?(urls.map(\.path))
        return true
    }

    private func fileURLs(from info: NSDraggingInfo) -> [URL] {
        let objects = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        return (objects as? [URL]) ?? []
    }
}
