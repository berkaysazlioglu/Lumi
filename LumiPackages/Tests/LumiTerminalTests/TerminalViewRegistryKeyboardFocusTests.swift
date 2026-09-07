import AppKit
import LumiKit
import XCTest
@testable import LumiTerminal

/// Klavye odağı köprüsü: store'un `focus(id)` kararı (Cmd+T spawn, Cmd+1..9,
/// focusNext, route dönüşü) AppKit first responder'a da taşınmalı. Önce yalnız
/// fare tıklaması first responder'ı değiştiriyordu — mor çerçeveli kart görsel
/// olarak seçili ama klavye girdisi başka yere akıyordu.
@MainActor
final class TerminalViewRegistryKeyboardFocusTests: XCTestCase {
    /// Bare `NSView` first responder olmayı reddeder; terminal view'ının
    /// `acceptsFirstResponder == true` davranışını temsil eder.
    private final class FocusableView: NSView {
        override var acceptsFirstResponder: Bool { true }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        return window
    }

    private func makeRegistry(id: TerminalID) -> (TerminalViewRegistry, FocusableView) {
        let registry = TerminalViewRegistry()
        let view = FocusableView()
        registry.register(view: view, for: id) { _ in }
        return (registry, view)
    }

    func testRequestOnAttachedViewMakesItFirstResponderImmediately() {
        // Arrange — view zaten bir pencerede (Cmd+2: mevcut kart)
        let id = TerminalID()
        let (registry, view) = makeRegistry(id: id)
        let window = makeWindow()
        let container = NSView()
        window.contentView?.addSubview(container)
        registry.attachView(for: id, into: container)
        XCTAssertFalse(window.firstResponder === view)

        // Act
        registry.requestKeyboardFocus(for: id)

        // Assert
        XCTAssertTrue(window.firstResponder === view, "kayıtlı ve pencerede olan view hemen first responder olmalı")
    }

    func testRequestBeforeAttachIsFulfilledOnAttach() {
        // Arrange — Cmd+T: spawn event'i store'a ulaşır ve focus(id) gelir,
        // ama SwiftUI host'u henüz view'ı bağlamamıştır.
        let id = TerminalID()
        let (registry, view) = makeRegistry(id: id)
        let window = makeWindow()
        let container = NSView()
        window.contentView?.addSubview(container)

        // Act
        registry.requestKeyboardFocus(for: id)
        XCTAssertFalse(window.firstResponder === view, "pencere yokken odak verilemez")
        registry.attachView(for: id, into: container)

        // Assert
        XCTAssertTrue(window.firstResponder === view, "bekleyen odak isteği attach'te yerine getirilmeli")
    }

    func testPendingRequestIsFulfilledWhenContainerLaterJoinsWindow() {
        // Arrange — host container makeNSView anında pencere hiyerarşisinde değil.
        let id = TerminalID()
        let (registry, view) = makeRegistry(id: id)
        let container = NSView()
        registry.attachView(for: id, into: container)
        registry.requestKeyboardFocus(for: id)

        // Act — container pencereye girer; host viewDidMoveToWindow'da tetikler
        let window = makeWindow()
        window.contentView?.addSubview(container)
        registry.fulfillPendingKeyboardFocus()

        // Assert
        XCTAssertTrue(window.firstResponder === view)
    }

    func testFulfilledRequestDoesNotReclaimFocusOnLaterAttach() {
        // Bir kez yerine getirilen istek bayatlar: kullanıcı başka yere (örn.
        // arama kutusu) tıkladıktan sonra bir layout/reattach odağı geri ÇALMAMALI.
        let id = TerminalID()
        let (registry, view) = makeRegistry(id: id)
        let window = makeWindow()
        let container = NSView()
        window.contentView?.addSubview(container)
        registry.attachView(for: id, into: container)
        registry.requestKeyboardFocus(for: id)
        XCTAssertTrue(window.firstResponder === view)

        let other = FocusableView()
        window.contentView?.addSubview(other)
        window.makeFirstResponder(other)

        // Act — reassert/reattach
        let newContainer = NSView()
        window.contentView?.addSubview(newContainer)
        registry.attachView(for: id, into: newContainer)
        registry.fulfillPendingKeyboardFocus()

        // Assert
        XCTAssertTrue(window.firstResponder === other, "yerine getirilmiş istek odağı geri çaldı")
    }

    func testCancelDropsPendingRequest() {
        // setFocused(nil) (yüzey arka plana alındı) bekleyen isteği düşürür.
        let id = TerminalID()
        let (registry, view) = makeRegistry(id: id)
        let window = makeWindow()
        let container = NSView()
        window.contentView?.addSubview(container)

        registry.requestKeyboardFocus(for: id)
        registry.cancelPendingKeyboardFocus()
        registry.attachView(for: id, into: container)

        XCTAssertFalse(window.firstResponder === view)
    }

    func testRequestForUnknownIDIsIgnored() {
        let registry = TerminalViewRegistry()
        registry.requestKeyboardFocus(for: TerminalID())
        registry.fulfillPendingKeyboardFocus() // çökmemeli
    }

    func testUnregisterClearsPendingRequest() {
        let id = TerminalID()
        let (registry, view) = makeRegistry(id: id)
        registry.requestKeyboardFocus(for: id)
        registry.unregister(id)

        // Yeniden kayıt (aynı id ile) bayat isteği devralmamalı
        let window = makeWindow()
        let container = NSView()
        window.contentView?.addSubview(container)
        registry.register(view: view, for: id) { _ in }
        registry.attachView(for: id, into: container)

        XCTAssertFalse(window.firstResponder === view)
    }
}
