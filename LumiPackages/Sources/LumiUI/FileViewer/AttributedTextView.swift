import AppKit
import SwiftUI

/// Salt-okunur, koyu temalı kod/diff görüntüleyici (NSTextView + TextKit).
/// Satır kaydırma kapalı — kod yatay scroll'lanır (FileViewer paritesi).
struct AttributedTextView: NSViewRepresentable {
    let text: NSAttributedString

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
        textView.textContainerInset = NSSize(width: 8, height: 8)

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

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.textStorage?.isEqual(to: text) != true {
            textView.textStorage?.setAttributedString(text)
            textView.scroll(.zero)
        }
    }
}
