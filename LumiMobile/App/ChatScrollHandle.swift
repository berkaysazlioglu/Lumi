// LumiMobile/App/ChatScrollHandle.swift
import SwiftUI
import UIKit

/// Decision 131: the UIScrollView behind the chat's SwiftUI ScrollView. SwiftUI
/// can neither tell a user scroll from content growth nor stop momentum — a
/// `scrollTo` issued mid-fling loses to the deceleration — so the chat reads
/// both from here.
@MainActor
final class ChatScrollHandle {
    weak var scrollView: UIScrollView?
    /// Latest geometry (per-frame values — kept out of @State so scrolling does not
    /// re-render the chat each frame; only derived flags are state).
    var sentinelMinY: CGFloat?
    var viewportHeight: CGFloat = 0

    /// Finger down or momentum: the user is moving the list.
    var isUserScrolling: Bool {
        guard let scrollView else { return false }
        return scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
    }

    /// Ends a fling where it is, so the jump that follows wins.
    func stopMomentum() {
        guard let scrollView, scrollView.isDecelerating || scrollView.isDragging else { return }
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
    }
}

/// Placed inside the ScrollView's content; finds the enclosing UIScrollView once
/// it is in a window and hands it to the handle.
struct ChatScrollViewFinder: UIViewRepresentable {
    let handle: ChatScrollHandle

    func makeUIView(context: Context) -> FinderView {
        let view = FinderView()
        view.handle = handle
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: FinderView, context: Context) {
        uiView.handle = handle
        uiView.attach()
    }

    final class FinderView: UIView {
        weak var handle: ChatScrollHandle?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attach()
        }

        func attach() {
            guard window != nil, let handle else { return }
            var view = superview
            while let current = view {
                if let scrollView = current as? UIScrollView {
                    handle.scrollView = scrollView
                    return
                }
                view = current.superview
            }
        }
    }
}
