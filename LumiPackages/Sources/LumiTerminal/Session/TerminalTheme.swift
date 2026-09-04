import AppKit
import SwiftTerm

/// Terminal renk paleti — tek sabit palet (Lumi, v1 xterm.js paritesi; karar 26:
/// kullanıcı seçimli tema sistemi kaldırıldı). NSColor Sendable olmadığından
/// renkler UInt32 hex olarak saklanır; apply(to:) MainActor'da çağrılmalıdır.
public struct TerminalTheme: Equatable, Sendable {
    public let backgroundHex: UInt32
    public let foregroundHex: UInt32
    public let cursorHex: UInt32
    public let cursorTextHex: UInt32
    /// ARGB formatında (0xAARRGGBB): alpha alanı opacity'yi taşır.
    public let selectionHex: UInt32
    /// 16-elemanlı ANSI palet (0–7 normal, 8–15 bright). Her eleman 0xRRGGBB.
    public let ansiHex: [UInt32]

    // MARK: - NSColor helpers (non-Sendable, sadece MainActor'da kullan)

    @MainActor public var backgroundColor: NSColor { nsColor(backgroundHex) }
    @MainActor public var foregroundColor: NSColor { nsColor(foregroundHex) }
    @MainActor public var cursorColor: NSColor { nsColor(cursorHex) }
    @MainActor public var cursorTextColor: NSColor { nsColor(cursorTextHex) }
    @MainActor public var selectionColor: NSColor {
        let alpha = CGFloat((selectionHex >> 24) & 0xFF) / 255.0
        return nsColor(selectionHex & 0x00FFFFFF).withAlphaComponent(alpha)
    }

    // MARK: - SwiftTerm uygulama

    @MainActor
    public func apply(to view: TerminalView) {
        view.nativeBackgroundColor = backgroundColor
        view.nativeForegroundColor = foregroundColor
        view.caretColor = cursorColor
        view.caretTextColor = cursorTextColor
        view.selectedTextBackgroundColor = selectionColor
        view.installColors(swiftTermPalette)
    }

    // MARK: - Lumi paleti (v1 src/renderer/components/Terminal/constants.ts)

    public static let lumi = TerminalTheme(
        backgroundHex:  0x12121F,
        foregroundHex:  0xE2E2F0,
        cursorHex:      0xA78BFA,
        cursorTextHex:  0x12121F,
        selectionHex:   0x4D8B5CF6, // 0x8B5CF6 @ ~30% opacity
        ansiHex: [
            0x0A0A12, // 0: black
            0xF87171, // 1: red
            0x4ADE80, // 2: green
            0xFBBF24, // 3: yellow
            0xA78BFA, // 4: blue
            0x8B5CF6, // 5: magenta
            0x22D3EE, // 6: cyan
            0xE2E2F0, // 7: white
            0x4A4A6A, // 8: bright black
            0xF87171, // 9: bright red
            0x4ADE80, // 10: bright green
            0xFBBF24, // 11: bright yellow
            0xA78BFA, // 12: bright blue
            0x8B5CF6, // 13: bright magenta
            0x22D3EE, // 14: bright cyan
            0xFFFFFF, // 15: bright white
        ]
    )

    // MARK: - Private helpers

    private var swiftTermPalette: [SwiftTerm.Color] {
        ansiHex.map { hex in
            SwiftTerm.Color(
                red:   UInt16((hex >> 16) & 0xFF) * 257,
                green: UInt16((hex >>  8) & 0xFF) * 257,
                blue:  UInt16( hex        & 0xFF) * 257
            )
        }
    }

    private func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed:   CGFloat((hex >> 16) & 0xFF) / 255,
            green:     CGFloat((hex >>  8) & 0xFF) / 255,
            blue:      CGFloat( hex        & 0xFF) / 255,
            alpha:     1
        )
    }
}
