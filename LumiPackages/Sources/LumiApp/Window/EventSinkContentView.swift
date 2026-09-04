import AppKit

/// Pencerenin contentView'ı: SwiftUI hosting view'ını ve onun ÜSTÜNDEKİ AppKit
/// etkileşim katmanlarını (`TabStripInteractionView`) kardeş olarak barındırır.
/// Hosting view'ın işlemeyip responder zincirine bıraktığı mouse event'lerini
/// yutar (NSThemeFrame'e sızmaz). Pencere sürüklemesi yalnız `WindowDragArea`'nın
/// açık `performDrag` çağrısıyla yapılır.
final class EventSinkContentView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}
