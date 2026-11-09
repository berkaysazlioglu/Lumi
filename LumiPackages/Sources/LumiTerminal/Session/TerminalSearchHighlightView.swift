import AppKit

/// Terminal aramasının vurguları (karar 144). Link altı çizgisi gibi terminal
/// view'ının üstünde, olaylara kör bir katmandır; SwiftTerm'in seçimine
/// dayanmaz — seçim her çıktı beslemesinde (`feedPrepare`) siliniyor, akan
/// bir Claude oturumunda etkin eşleşme görünmez olurdu.
final class TerminalSearchHighlightView: NSView {
    struct Span: Equatable {
        /// Görünür alanın 0 tabanlı ekran satırı.
        let row: Int
        let columns: Range<Int>
        let isActive: Bool
    }

    var spans: [Span] = [] {
        didSet { if spans != oldValue { needsDisplay = true } }
    }

    var cellSize: CGSize = .zero {
        didSet { if cellSize != oldValue { needsDisplay = true } }
    }

    // Orca'nın xterm dekorasyon renkleri (`TerminalSearch.tsx`, #612): tema
    // ne olursa olsun seçilebilsinler diye sabittir. Katman metnin ÜSTÜNDE
    // çizildiği için dolgular yarı saydamdır — glifler okunur kalır.
    private static let matchFill = NSColor(srgbRed: 0x5C / 255, green: 0x4A / 255, blue: 0, alpha: 0.55)
    private static let activeFill = NSColor(srgbRed: 0xC4 / 255, green: 0x58 / 255, blue: 0x0E / 255, alpha: 0.55)
    private static let activeBorder = NSColor(srgbRed: 1, green: 0xCF / 255, blue: 0x6B / 255, alpha: 1)
    private static let borderWidth: CGFloat = 1

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard !spans.isEmpty, cellSize.width > 0, cellSize.height > 0 else { return }
        // Etkin eşleşme en son çizilir; komşu eşleşmenin dolgusu kenarını örtmez.
        for span in spans.sorted(by: { !$0.isActive && $1.isActive }) {
            let rect = NSRect(
                x: CGFloat(span.columns.lowerBound) * cellSize.width,
                y: CGFloat(span.row) * cellSize.height,
                width: CGFloat(span.columns.count) * cellSize.width,
                height: cellSize.height
            )
            guard rect.intersects(dirtyRect) else { continue }
            (span.isActive ? Self.activeFill : Self.matchFill).setFill()
            rect.fill()
            if span.isActive {
                Self.activeBorder.setStroke()
                let border = NSBezierPath(rect: rect.insetBy(dx: Self.borderWidth / 2, dy: Self.borderWidth / 2))
                border.lineWidth = Self.borderWidth
                border.stroke()
            }
        }
    }
}
