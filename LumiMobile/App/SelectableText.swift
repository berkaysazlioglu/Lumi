// LumiMobile/App/SelectableText.swift
import SwiftUI
import UIKit

/// Read-only text that supports range selection (drag handles, Copy / Look Up),
/// unlike SwiftUI `Text.textSelection` which on iOS only copies the whole text.
/// Backed by a non-editable, non-scrolling `UITextView`.
///
/// `wraps == false` lays the text out on its natural width (code blocks inside
/// a horizontal ScrollView).
struct SelectableText: UIViewRepresentable {
    let text: NSAttributedString
    var wraps = true

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = []
        view.adjustsFontForContentSizeCategory = true
        view.linkTextAttributes = [.foregroundColor: UIColor.tintColor]
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.attributedText != text { view.attributedText = text }
        view.textContainer.lineBreakMode = wraps ? .byWordWrapping : .byClipping
        view.textContainer.widthTracksTextView = wraps
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: UITextView, context: Context) -> CGSize? {
        if wraps {
            let width = proposal.width ?? UIScreen.main.bounds.width
            let fitted = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            return CGSize(width: width, height: ceil(fitted.height))
        }
        let bounds = text.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let size = CGSize(width: ceil(bounds.width) + 1, height: ceil(bounds.height))
        view.textContainer.size = CGSize(width: size.width, height: .greatestFiniteMagnitude)
        return size
    }
}
