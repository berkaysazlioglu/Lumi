import AppKit
import SwiftTerm

/// Oturumun kalıcı emülatör view'ını üreten fabrika (Faz 4.1 / DIP).
/// `TerminalSession` view'ı kendi `new`'lemez; böylece oturum mantığı
/// AppKit alt sınıfından bağımsız test edilir.
@MainActor
protocol TerminalViewMaking {
    func makeView(frame: NSRect, font: NSFont) -> TerminalView
}

/// Dosya sürükle-bırak kabul eden view'lar (karar 11: path quote'lanır).
/// Fabrika `TerminalView` döndürdüğü için yetenek bu dar protokolle sorulur.
@MainActor
protocol FileDropAccepting: AnyObject {
    var onFileDrop: (([String]) -> Void)? { get set }
}

extension DropAwareTerminalView: FileDropAccepting {}

/// Üretim implementasyonu: Lumi temalı, drop-farkında SwiftTerm view'ı.
@MainActor
struct DropAwareTerminalViewMaker: TerminalViewMaking {
    func makeView(frame: NSRect, font: NSFont) -> TerminalView {
        DropAwareTerminalView(frame: frame, font: font)
    }
}
