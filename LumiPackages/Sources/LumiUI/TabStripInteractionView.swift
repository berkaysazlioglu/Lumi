import AppKit

/// Tab şeridinin seç / sürükle / hover etkileşimini işleyen AppKit katmanı.
/// Hosting view'ın KARDEŞİ olarak (üstünde) contentView'a eklenir — hosting
/// içinde olsaydı SwiftUI, titlebar bölgesindeki basışı pencere sürüklemesine
/// çevirirdi (bkz. `TabStripInteractionModel`). Electron `-webkit-app-region:
/// no-drag` paritesi.
///
/// Yalnız chip bölgelerinde hit alır (`hitTest`), kapatma butonu bölgesi ve
/// chip dışı her yer alttaki SwiftUI'ye düşer. Sürükleme mouseDown içinde
/// tracking loop ile tüketilir (NSControl paritesi); mouseUp'ta eşik altı =
/// seçim, eşik üstü = drop (`dropTarget` → onMove).
@MainActor
public final class TabStripInteractionView: NSView {
    private let model: TabStripInteractionModel
    private let onSelect: (String) -> Void
    private let onMove: (_ tab: String, _ target: String) -> Void
    private var trackingArea: NSTrackingArea?

    public init(
        frame: NSRect,
        model: TabStripInteractionModel,
        onSelect: @escaping (String) -> Void,
        onMove: @escaping (_ tab: String, _ target: String) -> Void
    ) {
        self.model = model
        self.onSelect = onSelect
        self.onMove = onMove
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unsupported") }

    /// SwiftUI `.global` frame'leri top-left origin'li — aynı uzayda kal.
    public override var isFlipped: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { dbg("mouseDownCanMoveWindow queried"); return false }

    private func dbg(_ m: String) {
        let line = "[ivdbg] \(m)\n"
        if let h = FileHandle(forWritingAtPath: "/tmp/lumi-overlay.log") { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
        else { try? line.write(toFile: "/tmp/lumi-overlay.log", atomically: true, encoding: .utf8) }
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        if ProcessInfo.processInfo.environment["LUMI_PROBE_MODE"] != nil { return super.hitTest(point) }
        let local = convert(point, from: superview)
        dbg("hitTest point=\(point) local=\(local) frame=\(frame) frames=\(model.chipFrames)")
        guard let tab = tab(at: local), let chip = model.chipFrames[tab] else { return nil }
        if TabStripInteractionModel.closeButtonRect(in: chip).contains(local) { return nil }
        return self
    }

    private func tab(at point: NSPoint) -> String? {
        model.chipFrames.first { $0.value.contains(point) }?.key
    }

    // MARK: - Hover (SwiftUI onHover kardeş katmanın altında kalır — buradan beslenir)

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if ProcessInfo.processInfo.environment["LUMI_PROBE_MODE"] != nil { return }
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    public override func mouseMoved(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let tab = tab(at: local)
        if model.hoveredTab != tab { model.hoveredTab = tab }
    }

    public override func mouseExited(with event: NSEvent) {
        if model.hoveredTab != nil { model.hoveredTab = nil }
    }

    // MARK: - Seç / sürükle

    public override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard let tab = tab(at: local), let window else { return }
        dbg("mouseDown tab=\(tab)")
        // Server-side titlebar sürüklemesi ~13px eşiğinde başlar ve o anda
        // isMovable'a bakar: yalnız bu tracking süresince pencere taşınamaz.
        let wasMovable = window.isMovable
        window.isMovable = false
        defer { window.isMovable = wasMovable }
        let originX = event.locationInWindow.x
        var hasMoved = false
        var lastDX: CGFloat = 0
        defer { model.dragging = nil }
        while let next = window.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            let dx = next.locationInWindow.x - originX
            if next.type == .leftMouseUp {
                if hasMoved { finishDrag(tab, dx: dx) } else { onSelect(tab) }
                return
            }
            dbg("dragged dx=\(dx) winX=\(window.frame.origin.x) moved=\(hasMoved)")
            guard hasMoved || abs(dx) >= TabStripInteractionModel.dragThreshold else { continue }
            hasMoved = true
            lastDX = dx
            if ProcessInfo.processInfo.environment["LUMI_NO_MODEL_WRITE"] == nil {
                model.dragging = .init(tab: tab, translation: dx)
            }
        }
        if hasMoved { finishDrag(tab, dx: lastDX) }
    }

    private func finishDrag(_ tab: String, dx: CGFloat) {
        guard let target = TabStripInteractionModel.dropTarget(
            for: tab, translation: dx, frames: model.chipFrames
        ) else { return }
        onMove(tab, target)
    }
}
