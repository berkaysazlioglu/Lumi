import AppKit
import XCTest

@testable import LumiKit

@MainActor
final class TerminalGridFitTests: XCTestCase {
    /// Hücre geometrisi bildiren sahte view (SwiftTerm'in 13pt'lik hücresine yakın).
    private final class GridView: NSView, TerminalGridSizing {
        var cellSize = CGSize(width: 8, height: 16)
    }

    func testLeftoverIsSplitEvenlyInsteadOfFallingToBottomRight() {
        // Arrange: 405×310 host → 50×19 hücrelik ızgara = 400×304; artık 5×6.
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 405, height: 310))
        let view = GridView()
        host.addSubview(view)

        // Act
        let didChange = TerminalGridFit.fit(view, in: host)

        // Assert
        XCTAssertTrue(didChange)
        XCTAssertEqual(view.frame.size, CGSize(width: 400, height: 304))
        XCTAssertEqual(view.frame.minX, 2.5, accuracy: 0.001)
        XCTAssertEqual(view.frame.minY, 3, accuracy: 0.001)
        XCTAssertEqual(host.bounds.maxX - view.frame.maxX, 2.5, accuracy: 0.001)
        XCTAssertEqual(host.bounds.maxY - view.frame.maxY, 3, accuracy: 0.001)
    }

    func testExactMultipleHostLeavesNoGap() {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 304))
        let view = GridView()
        host.addSubview(view)

        TerminalGridFit.fit(view, in: host)

        XCTAssertEqual(view.frame, host.bounds)
    }

    func testRefitIsIdempotent() {
        // Her layout'ta çağrılır: delta yoksa redraw/onRedraw tetiklenmemeli.
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 405, height: 310))
        let view = GridView()
        host.addSubview(view)

        XCTAssertTrue(TerminalGridFit.fit(view, in: host))
        XCTAssertFalse(TerminalGridFit.fit(view, in: host))
        XCTAssertFalse(TerminalGridFit.fit(view, in: host))
    }

    func testFontChangeRefitsWithNewCellSize() {
        // Font büyüyünce hücre büyür: ızgara küçülür ve yeni artık yine ortalanır.
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 405, height: 310))
        let view = GridView()
        host.addSubview(view)
        TerminalGridFit.fit(view, in: host)

        view.cellSize = CGSize(width: 10, height: 20)

        XCTAssertTrue(TerminalGridFit.fit(view, in: host))
        XCTAssertEqual(view.frame.size, CGSize(width: 400, height: 300))
        XCTAssertEqual(view.frame.minY, 5, accuracy: 0.001)
    }

    func testHostSmallerThanOneCellKeepsOneCell() {
        // Izgarayı sıfıra düşürmek emülatörü 0 sütuna resize ederdi.
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 5, height: 9))
        let view = GridView()
        host.addSubview(view)

        TerminalGridFit.fit(view, in: host)

        XCTAssertEqual(view.frame.size, CGSize(width: 8, height: 16))
    }

    func testEmptyHostBoundsLeavesFrameUntouched() {
        // Tab değişimi: makeNSView anında host 0×0 — emülatör sıfıra küçültülmemeli.
        let host = NSView()
        let view = GridView(frame: NSRect(x: 0, y: 0, width: 800, height: 480))

        XCTAssertFalse(TerminalGridFit.fit(view, in: host))
        XCTAssertEqual(view.frame.size, CGSize(width: 800, height: 480))
    }

    func testViewWithoutGridGeometryFillsHostBounds() {
        // Izgara bildirmeyen view (test double'ları / ileride başka bir host içeriği).
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 405, height: 310))
        let view = NSView()
        host.addSubview(view)

        XCTAssertTrue(TerminalGridFit.fit(view, in: host))
        XCTAssertEqual(view.frame, host.bounds)
    }
}
