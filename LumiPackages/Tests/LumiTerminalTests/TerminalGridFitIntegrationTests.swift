import AppKit
import LumiKit
import XCTest

@testable import LumiTerminal

/// `TerminalGridFit`'in aritmetiğinin SwiftTerm'in kendi yuvarlamasıyla uyuştuğunu
/// gerçek emülatör view'ı üzerinde doğrular (LumiKit tarafındaki testler sahte
/// hücre boyutuyla çalışır; buradaki asıl varsayım: ızgara boyutuna küçültmek
/// satır/sütun sayısını DEĞİŞTİRMEZ, dolayısıyla ek PTY resize doğmaz).
@MainActor
final class TerminalGridFitIntegrationTests: XCTestCase {
    private func makeView() -> DropAwareTerminalView {
        DropAwareTerminalView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 480),
            font: .monospacedSystemFont(ofSize: 13, weight: .regular)
        )
    }

    func testFittedFrameKeepsColsAndRows() {
        // Arrange: hücre boyutunun tam katı olmayan, kasıtlı olarak "kirli" bir host.
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 617, height: 433))
        let view = makeView()
        host.addSubview(view)
        view.frame = host.bounds // tam bounds: SwiftTerm satır/sütunu buradan hesaplar
        let expectedCols = view.getTerminal().cols
        let expectedRows = view.getTerminal().rows

        // Act
        TerminalGridFit.fit(view, in: host)

        // Assert
        XCTAssertEqual(view.getTerminal().cols, expectedCols)
        XCTAssertEqual(view.getTerminal().rows, expectedRows)
    }

    func testFittedFrameIsCenteredAndIdempotent() {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 617, height: 433))
        let view = makeView()
        host.addSubview(view)

        XCTAssertTrue(TerminalGridFit.fit(view, in: host))

        // Üstteki ve alttaki boşluk 1 backing piksel toleransında eşit olmalı —
        // düzeltmeden önce artığın tamamı (bir satır yüksekliğine kadar) alta düşüyordu.
        let topGap = host.bounds.maxY - view.frame.maxY
        let bottomGap = view.frame.minY - host.bounds.minY
        XCTAssertEqual(topGap, bottomGap, accuracy: 0.5)
        let leftGap = view.frame.minX - host.bounds.minX
        let rightGap = host.bounds.maxX - view.frame.maxX
        XCTAssertEqual(leftGap, rightGap, accuracy: 0.5)

        // Her layout'ta çağrılır: delta yoksa redraw tetiklenmemeli.
        XCTAssertFalse(TerminalGridFit.fit(view, in: host))
    }
}
