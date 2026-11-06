import AppKit

/// Uzak bir hub'daki terminalin yerel aynası (docs/design/08): hub'ın ham PTY
/// akışını çizer ve klavye girişini `onInput` ile geri verir. Hub'ın PTY'si
/// yeniden boyutlandırılmaz — ayna hub'ın `cols×rows` ızgarasını yazı boyutunu
/// ayarlayarak alana sığdırır. Implementasyon LumiTerminal'de (SwiftTerm).
@MainActor
public protocol RemoteTerminalMirroring: AnyObject {
    /// Aynanın kök view'ı; içeriği kendi bounds'una ortalar.
    var view: NSView { get }
    var onInput: ((Data) -> Void)? { get set }
    /// ⌘V / ⌃V'de yerel panodaki görselin ham baytları (karar 143 ek).
    var onPasteImage: ((Data) -> Void)? { get set }
    /// "Yazan kazanır" (karar 143 ek): klavyeyle yazılınca aynanın sığdığı ızgara istenir.
    var onGridRequest: ((TerminalGrid) -> Void)? { get set }
    func apply(_ chunk: RemoteTerminalChunk)
    /// Klavye odağını aynaya verir.
    func focus()
    /// Yerel terminal fontu (aile); boyut alana göre ayarlanır.
    func setFont(_ font: NSFont)
}

@MainActor
public protocol RemoteTerminalMirrorMaking: AnyObject {
    func makeMirror() -> any RemoteTerminalMirroring
}
