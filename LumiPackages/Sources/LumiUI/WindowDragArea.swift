import AppKit
import SwiftUI

/// Header'ın boş alanlarını native pencere title-bar'ı gibi davrandırır:
/// basılı tutup sürüklemek pencereyi taşır, çift tıklamak sistemin "başlık
/// çubuğuna çift tıkla" eylemini (zoom / minimize) uygular.
///
/// `.fullSizeContentView` ile content view title-bar'ı kapladığından AppKit
/// bu davranışı kendiliğinden vermez; v1'de (Electron) `-webkit-app-region:
/// drag` CSS'i sağlıyordu. SwiftUI tarafında karşılığı bu temsilcidir.
///
/// Header'ın arka katmanına yerleştirilir; üstteki butonlar kendi
/// tıklamalarını aldığından yalnızca boş alanlar pencereyi sürükler.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DraggableView() }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DraggableView: NSView {
        // mouseDown'u kendimiz işlediğimizden AppKit'in drag'ini devralmasını
        // istemiyoruz; aksi halde çift tıklama event'i bize hiç ulaşmaz.
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                Self.performDoubleClickAction(on: window)
            } else {
                window.performDrag(with: event)
            }
        }

        /// Sistemin "başlık çubuğuna çift tıkla" tercihini uygular
        /// (System Settings → Desktop & Dock).
        private static func performDoubleClickAction(on window: NSWindow) {
            let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
            switch action {
            case "Minimize": window.performMiniaturize(nil)
            case "None": break
            default: window.performZoom(nil) // "Maximize"
            }
        }
    }
}
