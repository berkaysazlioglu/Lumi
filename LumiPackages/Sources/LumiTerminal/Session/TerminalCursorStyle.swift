import LumiKit
import SwiftTerm

/// `TerminalCursorShape` (+ blink) → SwiftTerm `CursorStyle` eşlemesi.
/// SwiftTerm import'u LumiTerminal'de yaşadığından çeviri de burada (LumiKit
/// enum'u rawValue String saklar, parse helper'ı orada).
///
/// Not: TUI uygulaması DECSCUSR escape'iyle bu seçimi ezebilir — son-kazanır
/// modeli; bilinçli (SwiftTerm caret'i otomatik günceller).
public enum TerminalCursorStyleMapper {
    public static func swiftTermStyle(
        shape: TerminalCursorShape,
        blink: Bool
    ) -> CursorStyle {
        switch (shape, blink) {
        case (.block, true):      return .blinkBlock
        case (.block, false):     return .steadyBlock
        case (.underline, true):  return .blinkUnderline
        case (.underline, false): return .steadyUnderline
        case (.bar, true):        return .blinkBar
        case (.bar, false):       return .steadyBar
        }
    }
}
