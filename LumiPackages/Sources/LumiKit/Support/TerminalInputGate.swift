import Foundation

/// Terminal scroll/hover event monitörünün geçici olarak bastırılması için
/// paylaşılan kapı. Settings/FileViewer gibi tam-ekran SwiftUI overlay'leri
/// açıkken, terminalin pencere-seviyesi `NSEvent` local monitörü (bkz.
/// `DropAwareTerminalView`) scroll event'lerini YAKALAMAMALI — yoksa imleç
/// overlay panelinin üstündeyken bile geometrik olarak bir terminalin bounds'u
/// içinde kaldığı için scroll, overlay'in `ScrollView`'i yerine arkadaki
/// terminale gider (Claude TUI alt-buffer + anyEvent mouse modunda bu belirgin).
///
/// `isSuppressed` true iken monitör event'i consume etmeden geçirir; AppKit'in
/// normal hit-test dağıtımı scroll'u üstteki overlay'e yönlendirir.
///
/// MainActor-bound tek-yön bayrak: yazan üst katman (LumiUI/RootView), okuyan
/// alt katman (LumiTerminal monitörü). Pencere-seviyesi monitör doğası gereği
/// global olduğundan paylaşılan tekil burada bilinçli ve KISS bir tercihtir.
@MainActor
public final class TerminalInputGate {
    public static let shared = TerminalInputGate()

    public var isSuppressed = false

    private init() {}
}
