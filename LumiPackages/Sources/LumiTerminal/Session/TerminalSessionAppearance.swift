import AppKit
import SwiftTerm

/// Oturumun görsel komut yüzü: hepsi `TerminalPresentation`'a devredilir
/// (Faz 4.1 / SRP). Sonlanmış oturumda tüm görsel komutlar sessizce düşer.
extension TerminalSession {
    var terminalView: TerminalView { presentation.view }

    /// Hücre boyutu değişti → host yeniden yerleşim yapmalı (katman sınırı:
    /// oturum superview'a dokunmaz). Bağlanmazsa superview fallback'i çalışır.
    var onLayoutInvalidated: (() -> Void)? {
        get { presentation.onLayoutInvalidated }
        set { presentation.onLayoutInvalidated = newValue }
    }

    /// Gizli→görünür geçişi (grid↔maximize round-trip, fullscreen) sonrası TUI'yi
    /// tüm ekranı yeniden çizmeye zorlar: buffer'dan tam çizim + SIGWINCH poke'u
    /// (TUI ancak SIGWINCH ile iç durumunu tazeler). MainActor'da çağrılır.
    func requestRepaint() {
        guard !isTerminated else { return }
        presentation.redrawFromBuffer()
        pokePTYRepaint()
    }

    func setCursorStyle(_ style: CursorStyle) {
        guard !isTerminated else { return }
        presentation.setCursorStyle(style)
    }

    func setFont(_ font: NSFont) {
        guard !isTerminated else { return }
        presentation.setFont(font)
    }
}
