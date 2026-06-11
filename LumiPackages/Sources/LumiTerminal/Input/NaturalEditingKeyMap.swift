import AppKit

/// Doğal metin düzenleme tuş eşlemeleri (iTerm "Natural Text Editing" dengi).
///
/// ^W/^U seçimi bilinçli: SwiftTerm'in meta yolu Option+Backspace için
/// ESC+DEL gönderiyordu; zsh vi modunda (viins) ESC mod değişimine dönüşüp
/// kullanıcıyı normal modda bırakıyordu — kelime silinmiyor, sonrasında tekli
/// backspace de işlemiyordu. ^W/^U emacs VE viins keymap'lerinin ikisinde de
/// kill-word/kill-line'dır. Ok tuşları için alt+arrow CSI'ı kullanılır
/// (ESC b/f aynı vicmd tuzağına düşer).
///
/// SwiftTerm `keyDown`'ı `public` (open değil) olduğundan override edilemez;
/// eşleme NSEvent local monitor ile dispatch'ten önce uygulanır
/// (TerminalSessionManager kurar).
enum NaturalEditingKeyMap {
    private enum KeyCode {
        static let backspace: UInt16 = 51
        static let leftArrow: UInt16 = 123
        static let rightArrow: UInt16 = 124
    }

    static func bytes(for event: NSEvent) -> [UInt8]? {
        guard event.type == .keyDown else { return nil }
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let flags = event.modifierFlags.intersection(relevant)
        switch (event.keyCode, flags) {
        case (KeyCode.backspace, [.option]):
            return [0x17] // ^W — backward-kill-word
        case (KeyCode.backspace, [.command]):
            return [0x15] // ^U — satır başına kadar sil
        case (KeyCode.leftArrow, [.option]):
            return Array("\u{1B}[1;3D".utf8)
        case (KeyCode.rightArrow, [.option]):
            return Array("\u{1B}[1;3C".utf8)
        default:
            return nil
        }
    }
}
