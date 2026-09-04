import AppKit
import LumiUI

/// Traffic light'ları header'ın dikey ortasına taşır (v1 `trafficLightPosition`
/// paritesi — Electron'un `RedrawTrafficLights` yaklaşımı).
///
/// Yalnız butonları kaydırmak yetmez: AppKit'in titlebar container'ı 28px'tir ve
/// butonlar onun dışına taşınca superview bounds'u hit-test'i kırpar — tıklama
/// yalnız container içinde kalan şeritte çalışır. Bu yüzden önce container
/// header yüksekliğine büyütülür, butonlar onun içinde ortalanır. AppKit
/// resize / fullscreen / yeniden gösterimde layout'u sıfırladığından bu
/// noktalardan yeniden uygulanır.
@MainActor
enum TrafficLightLayout {
    static let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

    static func apply(to window: NSWindow, headerHeight: CGFloat = TopBarMetrics.height) {
        if ProcessInfo.processInfo.environment["LUMI_NO_TLL"] != nil { return }
        let buttons = buttonTypes.compactMap { window.standardWindowButton($0) }
        guard let titlebarView = buttons.first?.superview,
              let container = titlebarView.superview else { return }

        // Container: pencerenin üstünden headerHeight kadar (frame koordinatı alt-orijinli)
        let windowHeight = container.superview?.bounds.height ?? window.frame.height
        container.frame = NSRect(
            x: container.frame.origin.x,
            y: windowHeight - headerHeight,
            width: container.frame.width,
            height: headerHeight
        )
        titlebarView.frame = container.bounds

        for button in buttons {
            let y = (headerHeight - button.frame.height) / 2
            button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: y))
        }
    }

    static func setHidden(_ hidden: Bool, in window: NSWindow) {
        for type in buttonTypes {
            window.standardWindowButton(type)?.isHidden = hidden
        }
        if !hidden { apply(to: window) } // tekrar gösterirken hizayı koru
    }
}
