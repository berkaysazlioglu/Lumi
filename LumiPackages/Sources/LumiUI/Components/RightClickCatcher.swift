import AppKit
import SwiftUI

/// Sağ tık (ve ctrl+tık) yakalayıcı: native `contextMenu` yerine Lumi'nin
/// `PopoverMenu`sunu açmak için (karar 53). Sol tık ve kaydırma alta geçer —
/// `hitTest` yalnız sağ tuş olaylarında kendini döndürür.
struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) { nsView.onRightClick = onRightClick }

    final class CatcherView: NSView {
        var onRightClick: () -> Void = {}

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, Self.isContextClick(event) else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) { onRightClick() }

        override func mouseDown(with event: NSEvent) {
            if Self.isContextClick(event) { onRightClick() } else { super.mouseDown(with: event) }
        }

        static func isContextClick(_ event: NSEvent) -> Bool {
            event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        }
    }
}

extension View {
    /// Görünümün üstüne sağ tık yakalayıcı bindirir; sol tık etkilenmez.
    func onRightClick(_ action: @escaping () -> Void) -> some View {
        overlay { RightClickCatcher(onRightClick: action) }
    }
}
