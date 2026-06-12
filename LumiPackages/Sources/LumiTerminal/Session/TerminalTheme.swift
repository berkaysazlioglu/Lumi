import AppKit
import SwiftTerm

/// Terminal renk teması — config'de saklanabilen, SwiftTerm'e uygulanabilen preset sistemi.
/// NSColor Sendable olmadığından renkler UInt32 hex olarak saklanır; NSColor computed
/// property ile üretilir. apply(to:) MainActor'da çağrılmalıdır.
public struct TerminalTheme: Equatable, Sendable, Identifiable {
    // MARK: - Public alanlar

    public let id: String      // config.json'da saklanan değer, ör. "lumi"
    public let name: String    // UI'da gösterilecek ad, ör. "Lumi"

    // Renkler — hex (0xRRGGBB). NSColor computed property ile üretilir.
    public let backgroundHex: UInt32
    public let foregroundHex: UInt32
    public let cursorHex: UInt32
    public let cursorTextHex: UInt32
    /// ARGB formatında (0xAARRGGBB): alpha alanı opacity'yi taşır.
    public let selectionHex: UInt32
    /// 16-elemanlı ANSI palet (0–7 normal, 8–15 bright). Her eleman 0xRRGGBB.
    public let ansiHex: [UInt32]

    /// UI picker'ında preview için öne çıkan renkler:
    /// background, foreground, cursor ve ilk 6 ANSI rengi.
    public var previewColors: [UInt32] {
        [backgroundHex, foregroundHex, cursorHex]
        + Array(ansiHex.prefix(6))
    }

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

    // MARK: - Preset erişimi

    /// Tüm preset'ler — UI picker sırası.
    public static let all: [TerminalTheme] = [
        .lumi, .dracula, .oneDark, .nord,
        .solarizedDark, .solarizedLight, .githubLight
    ]

    /// Mevcut Lumi teması — default.
    public static let lumi = TerminalThemePresets.lumi

    /// id'ye göre preset döner; bilinmeyen id → .lumi.
    public static func preset(id: String) -> TerminalTheme {
        all.first { $0.id == id } ?? .lumi
    }

    // MARK: - Özel preseller (dahili kısayollar)

    static let dracula      = TerminalThemePresets.dracula
    static let oneDark      = TerminalThemePresets.oneDark
    static let nord         = TerminalThemePresets.nord
    static let solarizedDark  = TerminalThemePresets.solarizedDark
    static let solarizedLight = TerminalThemePresets.solarizedLight
    static let githubLight  = TerminalThemePresets.githubLight

    // MARK: - Private helpers

    /// SwiftTerm 16-bit bileşen paleti (UInt32 hex → SwiftTerm.Color).
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
