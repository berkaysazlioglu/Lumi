import AppKit
import LumiUI

/// Traffic light'ları ince header'ın içine, diğer macOS uygulamalarındaki
/// doğal konuma yerleştirir (karar 30 — Orca `hiddenInset` paritesi: ilk buton
/// x=16, dikeyde bar ortası; butonlar arası standart 20pt adım).
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
    /// İlk butonun sol kenarı ve butonlar arası adım (AppKit standardı 12px buton + 8px boşluk).
    static let leadingInset: CGFloat = TopBarMetrics.trafficLightLeading
    static let buttonStride: CGFloat = 20

    static func apply(to window: NSWindow, headerHeight: CGFloat = TopBarMetrics.height) {
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

        for (index, button) in buttons.enumerated() {
            let x = leadingInset + CGFloat(index) * buttonStride
            let y = (headerHeight - button.frame.height) / 2
            button.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    static func setHidden(_ hidden: Bool, in window: NSWindow) {
        for type in buttonTypes {
            window.standardWindowButton(type)?.isHidden = hidden
        }
        if !hidden { apply(to: window) } // tekrar gösterirken hizayı koru
    }
}
