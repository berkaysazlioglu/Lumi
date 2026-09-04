import AppKit
import XCTest
import LumiUI
@testable import LumiAppCore

/// Traffic light geometrisi (karar 30). `TrafficLightLayout` saf bir fonksiyon
/// değil (NSWindow mutasyonu yapar) ama geometrisi gerçek bir pencere üzerinde
/// deterministik olarak doğrulanabilir.
@MainActor
final class TrafficLightLayoutTests: XCTestCase {
    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
    }

    func testMetricsMatchTopBar() {
        XCTAssertEqual(TrafficLightLayout.leadingInset, TopBarMetrics.trafficLightLeading)
        XCTAssertEqual(TrafficLightLayout.buttonStride, 20)
        XCTAssertEqual(
            TrafficLightLayout.buttonTypes,
            [.closeButton, .miniaturizeButton, .zoomButton]
        )
    }

    func testButtonsAreLaidOutOnTheLeadingStride() {
        let window = makeWindow()
        let headerHeight: CGFloat = TopBarMetrics.height

        TrafficLightLayout.apply(to: window, headerHeight: headerHeight)

        let buttons = TrafficLightLayout.buttonTypes.compactMap { window.standardWindowButton($0) }
        XCTAssertEqual(buttons.count, 3, "üç standart buton bekleniyor")
        for (index, button) in buttons.enumerated() {
            let expectedX = TrafficLightLayout.leadingInset
                + CGFloat(index) * TrafficLightLayout.buttonStride
            XCTAssertEqual(button.frame.origin.x, expectedX, accuracy: 0.01)
            let expectedY = (headerHeight - button.frame.height) / 2
            XCTAssertEqual(button.frame.origin.y, expectedY, accuracy: 0.01, "dikeyde ortalanmalı")
        }
    }

    /// Butonlar 28px'lik AppKit titlebar container'ının dışına taştığında
    /// hit-test kırpılır — container header yüksekliğine büyütülmeli.
    func testTitlebarContainerGrowsToHeaderHeight() {
        let window = makeWindow()
        let headerHeight: CGFloat = 36

        TrafficLightLayout.apply(to: window, headerHeight: headerHeight)

        guard let titlebarView = window.standardWindowButton(.closeButton)?.superview,
              let container = titlebarView.superview else {
            return XCTFail("titlebar container bulunamadı")
        }
        XCTAssertEqual(container.frame.height, headerHeight, accuracy: 0.01)
        XCTAssertEqual(titlebarView.frame, container.bounds)
    }

    func testCustomHeaderHeightRecentersButtons() {
        let window = makeWindow()
        let headerHeight: CGFloat = 60

        TrafficLightLayout.apply(to: window, headerHeight: headerHeight)

        let button = window.standardWindowButton(.closeButton)!
        XCTAssertEqual(
            button.frame.origin.y,
            (headerHeight - button.frame.height) / 2,
            accuracy: 0.01
        )
    }

    func testSetHiddenTogglesAllButtonsAndKeepsAlignment() {
        let window = makeWindow()

        TrafficLightLayout.setHidden(true, in: window)
        for type in TrafficLightLayout.buttonTypes {
            XCTAssertEqual(window.standardWindowButton(type)?.isHidden, true)
        }

        TrafficLightLayout.setHidden(false, in: window)
        for type in TrafficLightLayout.buttonTypes {
            XCTAssertEqual(window.standardWindowButton(type)?.isHidden, false)
        }
        // Yeniden gösterimde hizalama korunur (apply çağrılır).
        XCTAssertEqual(
            window.standardWindowButton(.closeButton)?.frame.origin.x,
            TrafficLightLayout.leadingInset
        )
    }

    /// Tekrar uygulamak (resize/fullscreen kancaları) sonucu değiştirmemeli.
    func testApplyIsIdempotent() {
        let window = makeWindow()

        TrafficLightLayout.apply(to: window)
        let first = TrafficLightLayout.buttonTypes.compactMap {
            window.standardWindowButton($0)?.frame
        }
        TrafficLightLayout.apply(to: window)
        let second = TrafficLightLayout.buttonTypes.compactMap {
            window.standardWindowButton($0)?.frame
        }

        XCTAssertEqual(first, second)
    }
}
