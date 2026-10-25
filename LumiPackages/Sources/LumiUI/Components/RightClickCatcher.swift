import AppKit
import SwiftUI

/// Sağ tık (ve ctrl+tık) yakalayıcı: native `contextMenu` yerine Lumi'nin
/// `PopoverMenu`sunu açmak için (karar 53). Sol tık ve kaydırma alta geçer —
/// `hitTest` yalnız sağ tuş olaylarında kendini döndürür.
struct RightClickCatcher: NSViewRepresentable {
    /// Tık noktası, görünümün sol üst köşesine göre (SwiftUI koordinatı).
    let onRightClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) { nsView.onRightClick = onRightClick }

    final class CatcherView: NSView {
        var onRightClick: (CGPoint) -> Void = { _ in }
        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, Self.isContextClick(event) else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) { onRightClick(location(of: event)) }

        override func mouseDown(with event: NSEvent) {
            if Self.isContextClick(event) { onRightClick(location(of: event)) } else { super.mouseDown(with: event) }
        }

        private func location(of event: NSEvent) -> CGPoint {
            convert(event.locationInWindow, from: nil)
        }

        static func isContextClick(_ event: NSEvent) -> Bool {
            event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        }
    }
}

extension View {
    /// Görünümün üstüne sağ tık yakalayıcı bindirir; sol tık etkilenmez.
    func onRightClick(_ action: @escaping () -> Void) -> some View {
        overlay { RightClickCatcher(onRightClick: { _ in action() }) }
    }

    /// Tık noktasını da veren biçim — geniş yüzeylerde (kart başlığı) menüyü
    /// görünümün ortasına değil tıklanan yere bağlamak için.
    func onRightClick(at action: @escaping (CGPoint) -> Void) -> some View {
        overlay { RightClickCatcher(onRightClick: action) }
    }
}
