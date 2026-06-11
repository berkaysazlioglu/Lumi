import AppKit
import SwiftTerm

/// Lumi terminal renk kurulumu — v1 xterm temasının birebir karşılığı
/// (spec/23; kaynak: v1 src/renderer/components/Terminal/constants.ts).
/// SwiftTerm default'ları (siyah zemin, beyaz caret) hiçbir oturumda görünmemeli.
enum TerminalTheme {
    static let background = NSColor(srgbRed: 0x12 / 255, green: 0x12 / 255, blue: 0x1F / 255, alpha: 1)
    static let foreground = NSColor(srgbRed: 0xE2 / 255, green: 0xE2 / 255, blue: 0xF0 / 255, alpha: 1)
    static let cursor = NSColor(srgbRed: 0xA7 / 255, green: 0x8B / 255, blue: 0xFA / 255, alpha: 1)
    static let selection = NSColor(srgbRed: 0x8B / 255, green: 0x5C / 255, blue: 0xF6 / 255, alpha: 0.3)

    /// 16'lı ANSI palet: 0–7 v1 temasından; 8–15 bright türevleri (v1 xterm.js
    /// default bright'larına bırakmıştı — palet pastel olduğundan aynı tonlar
    /// kullanılır, yalnız black/white parlaklaşır).
    /// SwiftTerm.Color sınıfı Sendable değil; her çağrıda taze inşa edilir.
    static var ansiPalette: [SwiftTerm.Color] { [
        color(0x0A0A12), // black
        color(0xF87171), // red
        color(0x4ADE80), // green
        color(0xFBBF24), // yellow
        color(0xA78BFA), // blue
        color(0x8B5CF6), // magenta
        color(0x22D3EE), // cyan
        color(0xE2E2F0), // white
        color(0x4A4A6A), // bright black
        color(0xF87171), // bright red
        color(0x4ADE80), // bright green
        color(0xFBBF24), // bright yellow
        color(0xA78BFA), // bright blue
        color(0x8B5CF6), // bright magenta
        color(0x22D3EE), // bright cyan
        color(0xFFFFFF), // bright white
    ] }

    @MainActor
    static func apply(to view: TerminalView) {
        view.nativeBackgroundColor = background
        view.nativeForegroundColor = foreground
        view.caretColor = cursor
        view.caretTextColor = background
        view.selectedTextBackgroundColor = selection
        view.installColors(ansiPalette)
    }

    /// 8-bit hex → SwiftTerm'in 16-bit bileşenleri (0xFF → 0xFFFF).
    private static func color(_ hex: UInt32) -> SwiftTerm.Color {
        SwiftTerm.Color(
            red: UInt16((hex >> 16) & 0xFF) * 257,
            green: UInt16((hex >> 8) & 0xFF) * 257,
            blue: UInt16(hex & 0xFF) * 257
        )
    }
}
