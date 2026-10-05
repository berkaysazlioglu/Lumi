import AppKit
import SwiftUI

/// Karar 113: `Both`'ta editör ↔ önizleme kaydırma senkronu.
///
/// Çapalar üst düzey markdown bloklarıdır: her bloğun kaynakta başladığı satır
/// (`MarkdownDocument.blockStartLines`) önizlemedeki dikey konumuyla eşlenir;
/// arası doğrusal ara değerdir. Hangi bölme kaydırılırsa o sürer — diğerinin
/// programatik kaydırması yeniden bildirim üretmez (`isApplying`). Bir bölme
/// en alttaysa diğeri de en alta gider (son blok kısa/uzun olabilir).
@MainActor
final class MarkdownScrollSync: NSObject {
    private weak var editor: NSScrollView?
    private weak var preview: NSScrollView?
    private var isApplying = false

    /// Önizleme bloklarının içerik üstüne göre konumu (blok indeksi → y).
    var blockOffsets: [Int: CGFloat] = [:]
    var blockStartLines: [Int] = []
    /// Editör metninin satır başları (UTF-16) — metin değişince düşer.
    private var lineStarts: [Int]?

    func attachEditor(_ scrollView: NSScrollView) {
        guard editor !== scrollView else { return }
        editor = scrollView
        observe(scrollView, selector: #selector(editorDidScroll))
    }

    func attachPreview(_ scrollView: NSScrollView) {
        guard preview !== scrollView else { return }
        preview = scrollView
        observe(scrollView, selector: #selector(previewDidScroll))
    }

    func editorTextChanged() { lineStarts = nil }

    private func observe(_ scrollView: NSScrollView, selector: Selector) {
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: selector, name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )
    }

    // MARK: - Yönler

    @objc private func editorDidScroll() {
        guard !isApplying, editor != nil, let preview, let map = map(), let line = editorTopLine() else { return }
        let target = isEditorAtBottom(topLine: line) ? CGFloat.greatestFiniteMagnitude : map.offset(forLine: line)
        apply(target, to: preview)
    }

    @objc private func previewDidScroll() {
        guard !isApplying, let editor, let preview, let map = map() else { return }
        if Self.isAtBottom(preview) {
            apply(.greatestFiniteMagnitude, to: editor)
        } else {
            scrollEditor(toLine: map.line(forOffset: Self.offset(of: preview)))
        }
    }

    // MARK: - Eşleme

    private func map() -> ScrollSyncMap? {
        guard let preview, let height = preview.documentView?.frame.height, !blockStartLines.isEmpty else { return nil }
        let anchors = blockStartLines.indices.compactMap { index in
            blockOffsets[index].map { ScrollSyncMap.Anchor(line: Double(blockStartLines[index]), offset: $0) }
        }
        let totalLines = Double((lineStarts ?? computeLineStarts())?.count ?? 1)
        return ScrollSyncMap(anchors: anchors, endLine: totalLines + 1, endOffset: height)
    }

    // MARK: - Editör (TextKit 1)

    private var editorTextView: NSTextView? { editor?.documentView as? NSTextView }

    /// Görünür ilk satır, kesirli (1 tabanlı): 12.5 = 12. satırın yarısı.
    func editorTopLine() -> Double? {
        guard let textView = editorTextView, let layout = textView.layoutManager,
              let container = textView.textContainer, let starts = lineStarts ?? computeLineStarts(),
              textView.string.utf16.count > 0 else { return nil }
        let y = max(0, Self.offset(of: editor) - textView.textContainerInset.height)
        let glyph = layout.glyphIndex(for: NSPoint(x: 0, y: y), in: container)
        let character = layout.characterIndexForGlyph(at: glyph)
        let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let fraction = rect.height > 0 ? min(max((y - rect.minY) / rect.height, 0), 1) : 0
        return Double(Self.lineIndex(of: character, in: starts) + 1) + fraction
    }

    /// Editörde dip, belge yüksekliğinden değil satırdan çıkarılır: büyük
    /// dosyada kesintili yerleşim açıktır ve yükseklik henüz tahmin olabilir.
    private func isEditorAtBottom(topLine: Double) -> Bool {
        guard let editor, let textView = editorTextView, let layout = textView.layoutManager,
              let starts = lineStarts ?? computeLineStarts() else { return false }
        let lineHeight = layout.defaultLineHeight(for: textView.font ?? .monospacedSystemFont(ofSize: 13, weight: .regular))
        guard lineHeight > 0 else { return false }
        let visibleLines = Double(editor.contentView.bounds.height / lineHeight)
        return topLine + visibleLines >= Double(starts.count) + 1
    }

    private func scrollEditor(toLine line: Double) {
        guard let editor, let textView = editorTextView, let layout = textView.layoutManager,
              let starts = lineStarts ?? computeLineStarts(), !starts.isEmpty else { return }
        let index = min(max(Int(line) - 1, 0), starts.count - 1)
        guard starts[index] < textView.string.utf16.count else {
            return apply(.greatestFiniteMagnitude, to: editor)
        }
        let glyph = layout.glyphIndexForCharacter(at: starts[index])
        let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let fraction = line - line.rounded(.down)
        apply(rect.minY + CGFloat(fraction) * rect.height + textView.textContainerInset.height, to: editor)
    }

    private func computeLineStarts() -> [Int]? {
        guard let text = editorTextView?.string else { return nil }
        var starts = [0]
        for (offset, unit) in text.utf16.enumerated() where unit == 0x0A { starts.append(offset + 1) }
        lineStarts = starts
        return starts
    }

    static func lineIndex(of character: Int, in starts: [Int]) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= character { low = mid } else { high = mid - 1 }
        }
        return low
    }

    // MARK: - NSScrollView yardımcıları

    /// İçerik üstünden itibaren kaydırma (çevrilmemiş belge görünümünde de).
    private static func offset(of scrollView: NSScrollView?) -> CGFloat {
        guard let scrollView, let document = scrollView.documentView else { return 0 }
        let clip = scrollView.contentView.bounds
        return document.isFlipped ? clip.minY : document.frame.height - clip.maxY
    }

    private static func isAtBottom(_ scrollView: NSScrollView) -> Bool {
        guard let document = scrollView.documentView else { return false }
        let maxOffset = document.frame.height - scrollView.contentView.bounds.height
        return maxOffset > 0 && offset(of: scrollView) >= maxOffset - 1
    }

    private func apply(_ offset: CGFloat, to scrollView: NSScrollView) {
        guard let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let maxOffset = max(0, document.frame.height - clip.bounds.height)
        let clamped = min(max(offset, 0), maxOffset)
        let originY = document.isFlipped ? clamped : maxOffset - clamped
        guard abs(clip.bounds.minY - originY) > 0.5 else { return }
        isApplying = true
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: originY))
        scrollView.reflectScrolledClipView(clip)
        isApplying = false
    }
}

/// Satır ↔ önizleme konumu eşlemesinin saf aritmetiği (birim testten görünür).
struct ScrollSyncMap {
    struct Anchor: Equatable {
        let line: Double
        let offset: CGFloat
    }

    /// Başlangıç (1. satır ↔ 0) + bloklar + bitiş; iki eksende de artan.
    let anchors: [Anchor]

    init(anchors blocks: [Anchor], endLine: Double, endOffset: CGFloat) {
        var sorted = [Anchor(line: 1, offset: 0)]
        for anchor in blocks.sorted(by: { $0.line < $1.line }) + [Anchor(line: endLine, offset: endOffset)] {
            guard let last = sorted.last, anchor.line > last.line, anchor.offset >= last.offset else { continue }
            sorted.append(anchor)
        }
        anchors = sorted
    }

    func offset(forLine line: Double) -> CGFloat {
        guard let upper = anchors.firstIndex(where: { $0.line > line }) else { return anchors.last?.offset ?? 0 }
        guard upper > 0 else { return 0 }
        let low = anchors[upper - 1]
        let high = anchors[upper]
        let fraction = CGFloat((line - low.line) / (high.line - low.line))
        return low.offset + fraction * (high.offset - low.offset)
    }

    func line(forOffset offset: CGFloat) -> Double {
        guard let upper = anchors.firstIndex(where: { $0.offset > offset }) else { return anchors.last?.line ?? 1 }
        guard upper > 0 else { return 1 }
        let low = anchors[upper - 1]
        let high = anchors[upper]
        let fraction = Double((offset - low.offset) / (high.offset - low.offset))
        return low.line + fraction * (high.line - low.line)
    }
}

/// SwiftUI `ScrollView`'un altındaki `NSScrollView`'u bulur (içeriğin arka
/// planına konur; pencereye girince çevreleyen kaydırma görünümünü bildirir).
struct EnclosingScrollViewReader: NSViewRepresentable {
    let onResolve: (NSScrollView) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.onResolve = onResolve
    }

    final class ProbeView: NSView {
        var onResolve: ((NSScrollView) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, let scrollView = self.enclosingScrollView else { return }
                self.onResolve?(scrollView)
            }
        }
    }
}

/// Üst düzey blokların içerik koordinatındaki üst kenarları.
struct MarkdownBlockOffsetsKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
