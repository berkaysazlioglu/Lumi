import AppKit
import LumiKit
import SwiftUI

/// Koyu temalı kod görüntüleyici/editörü (NSTextView + TextKit).
/// Satır kaydırma kapalı — kod yatay scroll'lanır (FileViewer paritesi).
///
/// Karar 110: `onTextChange` verilirse metin düzenlenebilir. Metin yalnız
/// `revision` değişince baştan basılır (yükleme / yeniden yükleme / vazgeçme);
/// aynı revizyonda gelen yeni `text` kullanıcının yazdığının vurgulanmış
/// hâlidir ve yalnız ATTRIBUTE'ları uygulanır — imleç, seçim, scroll ve undo
/// geçmişi korunur. Bu arada metin yeniden değiştiyse bayat vurgu atlanır.
struct AttributedTextView: NSViewRepresentable {
    let text: NSAttributedString
    var revision = 0
    /// Seçimin satır aralığı (karar 100 "Mention in Chat"); boş seçimde `nil`.
    var onSelectLines: ((ClosedRange<Int>?) -> Void)?
    /// Düzenleme açıksa her değişiklikte editörün tam metni.
    var onTextChange: ((String) -> Void)?
    /// Escape: NSTextView onu `complete:`'e çevirip modal'a ulaştırmıyordu.
    var onCancel: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.NS.bgDeep

        let textView = ViewerTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = Theme.NS.bgDeep
        textView.insertionPointColor = Theme.NS.textPrimary
        textView.textContainerInset = NSSize(width: Theme.scaled(8), height: Theme.scaled(8))
        // Kod düzenlenir: akıllı tırnak/tire, otomatik düzeltme ve link
        // algılama metni sessizce değiştirirdi.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = []
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelectLines = onSelectLines
        coordinator.onTextChange = onTextChange
        guard let textView = scrollView.documentView as? ViewerTextView,
              let storage = textView.textStorage else { return }
        textView.onCancel = onCancel
        textView.isEditable = onTextChange != nil

        if coordinator.revision != revision {
            coordinator.revision = revision
            coordinator.appliedText = text
            textView.undoManager?.removeAllActions()
            storage.setAttributedString(text)
            textView.typingAttributes = Self.typingAttributes(of: text)
            textView.scroll(.zero)
        } else if coordinator.appliedText !== text {
            coordinator.appliedText = text
            guard storage.string == text.string else { return }
            Self.applyAttributes(of: text, to: storage)
        }
    }

    /// Vurgunun yalnız stil katmanını mevcut metne giydirir.
    private static func applyAttributes(of source: NSAttributedString, to storage: NSTextStorage) {
        storage.beginEditing()
        source.enumerateAttributes(in: NSRange(location: 0, length: source.length)) { attributes, range, _ in
            storage.setAttributes(attributes, range: range)
        }
        storage.endEditing()
    }

    /// Yeni yazılan karakter vurgu gelene dek düz kod metni gibi görünür.
    private static func typingAttributes(of text: NSAttributedString) -> [NSAttributedString.Key: Any] {
        let font = text.length > 0 ? text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil
        return [
            .font: font ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: Theme.NS.textPrimary,
        ]
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSelectLines: ((ClosedRange<Int>?) -> Void)?
        var onTextChange: ((String) -> Void)?
        /// `-1`: henüz hiçbir metin basılmadı.
        var revision = -1
        var appliedText: NSAttributedString?

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let onSelectLines, let textView = notification.object as? NSTextView else { return }
            onSelectLines(CodeMention.lineRange(in: textView.string, selection: textView.selectedRange()))
        }

        func textDidChange(_ notification: Notification) {
            guard let onTextChange, let textView = notification.object as? NSTextView else { return }
            onTextChange(textView.string)
        }
    }
}

/// Escape'i modal kapatmaya bağlayan NSTextView.
final class ViewerTextView: NSTextView {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        if let onCancel {
            onCancel()
        } else {
            super.cancelOperation(sender)
        }
    }
}
