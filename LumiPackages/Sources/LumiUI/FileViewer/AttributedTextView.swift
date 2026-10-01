import AppKit
import LumiKit
import SwiftUI

/// Salt-okunur, koyu temalı kod/diff görüntüleyici (NSTextView + TextKit).
/// Satır kaydırma kapalı — kod yatay scroll'lanır (FileViewer paritesi).
struct AttributedTextView: NSViewRepresentable {
    let text: NSAttributedString
    /// Seçimin satır aralığı (karar 100 "Mention in Chat"); boş seçimde `nil`.
    var onSelectLines: ((ClosedRange<Int>?) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.NS.bgDeep

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = Theme.NS.bgDeep
        textView.textContainerInset = NSSize(width: Theme.scaled(8), height: Theme.scaled(8))

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
        context.coordinator.onSelectLines = onSelectLines
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.textStorage?.isEqual(to: text) != true {
            textView.textStorage?.setAttributedString(text)
            textView.scroll(.zero)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSelectLines: ((ClosedRange<Int>?) -> Void)?

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let onSelectLines, let textView = notification.object as? NSTextView else { return }
            onSelectLines(CodeMention.lineRange(in: textView.string, selection: textView.selectedRange()))
        }
    }
}
