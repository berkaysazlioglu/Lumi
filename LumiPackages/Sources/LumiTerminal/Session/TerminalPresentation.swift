import AppKit
import Foundation
import SwiftTerm

/// Oturumun **görsel** yüzü (Faz 4.1 / SRP): emülatöre besleme, font/caret
/// uygulaması ve yeniden çizim. PTY, akış kontrolü ve durum makinesi burada yok.
///
/// Katman sınırı: view'ın hierarchy'si (superview, layout) bu tipin dışındadır —
/// yeniden yerleşim ihtiyacı `onLayoutInvalidated` ile host'a bildirilir.
@MainActor
final class TerminalPresentation {
    let view: TerminalView

    /// Hücre boyutu değiştiği için ızgaranın kapladığı alan da değişti; host
    /// yeniden yerleşim yapmalı. Varsayılan, host bağlanana kadar geçerli olan
    /// superview fallback'idir (`TerminalViewRegistry`/host bunu ezebilir).
    var onLayoutInvalidated: (() -> Void)?

    init(view: TerminalView, scrollbackLines: Int) {
        self.view = view
        view.getTerminal().options.scrollback = scrollbackLines
        onLayoutInvalidated = { [weak view] in
            view?.superview?.needsLayout = true
        }
    }

    /// SwiftTerm `feed` SENKRON parse eder — dönüş "tüketildi" demektir
    /// (design/00 Ek A §A.1-2 ack noktası).
    func feed(_ batch: Data) {
        view.feed(byteArray: ArraySlice([UInt8](batch)))
    }

    /// Buffer'dan tam yeniden çizim, SIGWINCH poke'u OLMADAN. Frame-oturma
    /// yolunda (tab değişimi sonrası reassert, pencere resize) kullanılır —
    /// boyut değiştiyse SwiftTerm sizeChanged → PTY resize zinciri SIGWINCH'i
    /// zaten üretir; her layout frame'inde ek poke TUI'yi spam'lerdi.
    ///
    /// `updateFullScreen` tüm hücreleri dirty işaretler: reattach sonrası
    /// (dirty hücre kalmadığından `needsDisplay` tek başına boş çizerdi)
    /// emülatör buffer'ındaki son kare hem TUI hem düz bash için anında görünür.
    func redrawFromBuffer() {
        view.getTerminal().updateFullScreen()
        view.setNeedsDisplay(view.bounds)
    }

    /// Caret şekli + blink canlı uygular (Settings → Cursor). SwiftTerm caret'i
    /// otomatik günceller; ek redraw gerekmez.
    func setCursorStyle(_ style: CursorStyle) {
        view.getTerminal().setCursorStyle(style)
    }

    /// Font (aile + boyut) canlı uygular. SwiftTerm setter zinciri hücre
    /// boyutlarını yeniden hesaplar, resize'lar (PTY'ye SIGWINCH) ve needsDisplay
    /// işaretler; ardından host'tan yeniden yerleşim istenir (ortalama yalnız
    /// layout'ta yapılır — istenmezse boşluk bir sonraki resize'a dek kalırdı).
    func setFont(_ font: NSFont) {
        view.font = font
        onLayoutInvalidated?()
    }
}
