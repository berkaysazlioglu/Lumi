import SwiftUI
import UIKit

/// Typography of the Claude-TUI-style chat: the Mac's terminal font family
/// (empty = bundled JetBrains Mono, the Mac default) at the phone's own text
/// size (Settings ▸ Text Size, persisted on the phone).
struct TUIStyle: Equatable {
    /// Resolved font family that is actually available on the phone.
    let family: String?
    let size: CGFloat

    static let bundledFamily = "JetBrains Mono"
    static let sizeKey = "tuiFontSize"
    /// Mac `terminalFontSize` default.
    static let defaultSize: Double = 13
    static let sizeRange: ClosedRange<Double> = 10...20
    static let `default` = TUIStyle(macFamily: "", size: defaultSize)
    /// Font families never change while the app runs; scanned once (the style
    /// is rebuilt on every Projects broadcast).
    private static let installedFamilies = Set(UIFont.familyNames)

    /// `macFamily` comes from the Mac's `display.terminalFontFamily`; a family
    /// the phone doesn't have falls back to JetBrains Mono, then to SF Mono.
    init(macFamily: String, size: Double) {
        let wanted = macFamily.isEmpty ? Self.bundledFamily : macFamily
        if Self.installedFamilies.contains(wanted) {
            family = wanted
        } else {
            family = Self.installedFamilies.contains(Self.bundledFamily) ? Self.bundledFamily : nil
        }
        self.size = CGFloat(min(max(size, Self.sizeRange.lowerBound), Self.sizeRange.upperBound))
    }

    func font(bold: Bool = false, italic: Bool = false, scale: CGFloat = 1) -> UIFont {
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let pointSize = (size * scale).rounded()
        let base: UIFontDescriptor
        if let family {
            base = UIFontDescriptor(fontAttributes: [.family: family])
        } else {
            base = UIFont.monospacedSystemFont(ofSize: pointSize, weight: .regular).fontDescriptor
        }
        let descriptor = base.withSymbolicTraits(traits) ?? base
        return UIFont(descriptor: descriptor, size: pointSize)
    }

    var swiftUIFont: Font { Font(font()) }

    /// Width of one monospaced cell — hanging indents are counted in cells.
    var cellWidth: CGFloat {
        ("M" as NSString).size(withAttributes: [.font: font()]).width
    }
}

/// Claude Code TUI colors (its built-in dark/light themes) on Lumi surfaces.
enum TUIColors {
    static let text = LumiPalette.uiTextPrimary
    /// Dimmed text: tool results, `⎿`, hints.
    static let dim = pair(dark: 0x999999, light: 0x666666)
    /// Inline code, links — Claude's "permission" blue.
    static let code = pair(dark: 0xB1B9F9, light: 0x5769F7)
    static let success = pair(dark: 0x4EBA65, light: 0x2C7A39)
    static let error = pair(dark: 0xFF6B80, light: 0xAB2B3F)
    /// Claude brand orange (spinner/heading accents).
    static let claude = UIColor(hex: 0xD77757)
    /// The user prompt's band (`> …`).
    static let userBand = LumiPalette.themed(light: 0xEFEFF4, dark: 0x2C2C2E, lumi: 0x24243A)
    static let codeBand = LumiPalette.themed(light: 0xF4F4F8, dark: 0x1C1C1E, lumi: 0x1A1A2E)

    private static func pair(dark: UInt32, light: UInt32) -> UIColor {
        UIColor { UIColor(hex: $0.userInterfaceStyle == .dark ? dark : light) }
    }
}

private struct TUIStyleKey: EnvironmentKey {
    static let defaultValue = TUIStyle.default
}

extension EnvironmentValues {
    var tuiStyle: TUIStyle {
        get { self[TUIStyleKey.self] }
        set { self[TUIStyleKey.self] = newValue }
    }
}
