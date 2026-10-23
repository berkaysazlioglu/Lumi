import AppKit
import LumiKit
import SwiftUI

/// Docked yuvanın orta alana bakan kenarındaki sürükleme tutamacı (karar 125).
///
/// **Neden AppKit?** Terminal `anyEvent` fare modundayken `.mouseMoved` ve
/// SwiftUI hover'ı güvenilmez (karar 67/69). İmleç cursor rect'le, sürükleme
/// mouseDown alan view'a gelen `mouseDragged` ile yürür — ikisi de pencerenin
/// geri kalanından bağımsızdır. Tutamaç yalnız yuvanın kendi kenarını kaplar;
/// orta alanın (terminal) üstüne taşmaz.
///
/// Sürükleme sırasında genişlik `LayoutStore.previewWidth`'e (bellek), bırakınca
/// `commitWidth`'e (tek disk yazımı) iner. Çift tık yuvayı varsayılan
/// genişliğine döndürür. Auto-reveal overlay'inde çizilmez (`PanelHostView`).
struct PanelResizeHandle: NSViewRepresentable {
    let slot: PanelSlot

    @Shell private var shell

    /// Tıklanabilir şerit — 1px ayracın üstü + panelin içine birkaç piksel.
    static var hitWidth: CGFloat { Theme.scaled(6) }
    /// Hover/sürükleme vurgusunun kalınlığı.
    static var highlightWidth: CGFloat { Theme.scaled(2) }

    func makeNSView(context: Context) -> PanelResizeHandleView {
        PanelResizeHandleView()
    }

    func updateNSView(_ view: PanelResizeHandleView, context: Context) {
        let layout = shell.layout
        let slot = slot
        // Sol yuva sağ kenarından, sağdakiler sol kenarından büyür.
        let direction: Double = slot == .left ? 1 : -1
        view.edge = slot == .left ? .maxX : .minX
        view.highlightWidth = Self.highlightWidth
        view.highlightColor = NSColor(Theme.accentPrimary)
        view.onBegin = { layout.width(for: slot) }
        view.onDrag = { startWidth, delta in
            layout.previewWidth(startWidth + direction * delta, for: slot)
        }
        view.onEnd = { layout.commitWidth(for: slot) }
        view.onReset = { layout.setWidth(PanelLayout.defaultWidth(for: slot), for: slot) }
    }
}

final class PanelResizeHandleView: NSView {
    var edge: NSRectEdge = .minX
    var highlightWidth: CGFloat = 2
    var highlightColor: NSColor = .controlAccentColor
    /// Sürükleme başında yuvanın genişliğini döndürür.
    var onBegin: () -> Double = { 0 }
    var onDrag: (_ startWidth: Double, _ delta: Double) -> Void = { _, _ in }
    var onEnd: () -> Void = {}
    var onReset: () -> Void = {}

    private var dragStart: (x: CGFloat, width: Double)?
    private var isHovering = false {
        didSet { if isHovering != oldValue { needsDisplay = true } }
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            dragStart = nil
            onReset()
            return
        }
        dragStart = (event.locationInWindow.x, onBegin())
        // İmleç tutamaçtan taşsa da sürükleme boyunca resize kalsın.
        NSCursor.resizeLeftRight.push()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        onDrag(dragStart.width, Double(event.locationInWindow.x - dragStart.x))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragStart = nil
        NSCursor.pop()
        needsDisplay = true
        onEnd()
    }

    /// Sürükleme sürerken tutamaç kaldırıldıysa (panel ⌘J ile kapandı) mouseUp
    /// hiç gelmez: imleç ve canlı genişlik yine de bırakılır.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil, dragStart != nil else { return }
        dragStart = nil
        NSCursor.pop()
        onEnd()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHovering || dragStart != nil else { return }
        highlightColor.setFill()
        let x = edge == .minX ? bounds.minX : bounds.maxX - highlightWidth
        NSRect(x: x, y: bounds.minY, width: highlightWidth, height: bounds.height).fill()
    }
}
