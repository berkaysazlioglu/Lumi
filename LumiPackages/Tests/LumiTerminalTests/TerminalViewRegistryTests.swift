import AppKit
import LumiKit
import XCTest
@testable import LumiTerminal

/// TerminalViewRegistry reparenting davranışı (grid round-trip'te boş kart bug'ı).
@MainActor
final class TerminalViewRegistryTests: XCTestCase {
    private func makeRegistry(
        id: TerminalID
    ) -> (TerminalViewRegistry, NSView, () -> [Bool]) {
        let registry = TerminalViewRegistry()
        let view = NSView()
        var visibilityLog: [Bool] = []
        registry.register(view: view, for: id) { visibilityLog.append($0) }
        return (registry, view, { visibilityLog })
    }

    func testReattachThenStaleDetachKeepsViewInNewContainer() {
        // SwiftUI reparenting yarışı: yeni host attach eder, ARDINDAN eski host'un
        // dismantle'ı (bayat) gelir. Bayat detach canlı view'ı sökmemeli.
        let id = TerminalID()
        let (registry, view, _) = makeRegistry(id: id)
        let oldContainer = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let newContainer = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))

        registry.attachView(for: id, into: oldContainer)
        XCTAssertTrue(view.superview === oldContainer)

        // Grid rebuild: önce yeni container'a taşı
        registry.attachView(for: id, into: newContainer)
        XCTAssertTrue(view.superview === newContainer)

        // Eski host'un bayat dismantle'ı — view'ı yeni container'dan SÖKMEMELİ
        registry.detachView(for: id, from: oldContainer)
        XCTAssertTrue(view.superview === newContainer, "bayat detach canlı view'ı söktü")
    }

    func testDetachFromCurrentContainerRemovesView() {
        // Kart gerçekten kapanırken (doğru container'dan detach) view sökülmeli.
        let id = TerminalID()
        let (registry, view, _) = makeRegistry(id: id)
        let container = NSView()

        registry.attachView(for: id, into: container)
        XCTAssertTrue(view.superview === container)

        registry.detachView(for: id, from: container)
        XCTAssertNil(view.superview)
    }

    func testReattachMarksViewForRedraw() {
        // Re-attach sonrası buffer'dan tam çizim için needsDisplay set edilmeli
        // (grid round-trip'te "sadece input satırı geliyor" bug'ının ikinci yarısı).
        // Bare NSView window'suz needsDisplay'i tutmaz; setter'ı spy ile yakala.
        let id = TerminalID()
        let registry = TerminalViewRegistry()
        let spy = RedrawSpyView()
        registry.register(view: spy, for: id) { _ in }
        let container = NSView()

        registry.attachView(for: id, into: container)
        XCTAssertTrue(spy.redrawRequested)
    }

    func testVisibilityTogglesAcrossDetachReattach() {
        let id = TerminalID()
        let (registry, _, log) = makeRegistry(id: id)
        let container = NSView()

        // register → ilk visibility false (henüz bağlı değil)
        XCTAssertEqual(log(), [false])

        registry.attachView(for: id, into: container)
        XCTAssertEqual(log(), [false, true])

        registry.detachView(for: id, from: container)
        XCTAssertEqual(log(), [false, true, false])
    }
}

/// needsDisplay set'ini yakalayan spy (bare NSView window'suz değeri tutmaz).
private final class RedrawSpyView: NSView {
    var redrawRequested = false
    override var needsDisplay: Bool {
        willSet { if newValue { redrawRequested = true } }
    }
}
