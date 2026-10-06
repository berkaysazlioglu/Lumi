import AppKit

/// Hover'daki link'in altı çizgisi (karar 116). SwiftTerm'in kendi vurgusu
/// yalnız kendi regex'inin aralığını çizebildiği ve diske soramadığı için
/// kapalıdır; çizgi terminal view'ının üstünde, olaylara kör bu katmandadır.
final class TerminalLinkUnderlineView: NSView {
    /// Hücre ızgarasında çizilecek parçalar (ekran satırı + sütun aralığı).
    var spans: [TerminalLinkSpan] = [] {
        didSet { if spans != oldValue { needsDisplay = true } }
    }

    var cellSize: CGSize = .zero
    var color: NSColor = .labelColor

    /// Çizgi hücrenin alt kenarından bu kadar yukarıdadır (descender payı).
    private static let baselineInset: CGFloat = 2
    private static let thickness: CGFloat = 1

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard !spans.isEmpty, cellSize.width > 0, cellSize.height > 0 else { return }
        color.setFill()
        for span in spans {
            let rect = NSRect(
                x: CGFloat(span.columns.lowerBound) * cellSize.width,
                y: CGFloat(span.row + 1) * cellSize.height - Self.baselineInset,
                width: CGFloat(span.columns.count) * cellSize.width,
                height: Self.thickness
            )
            if rect.intersects(dirtyRect) { rect.fill() }
        }
    }
}
