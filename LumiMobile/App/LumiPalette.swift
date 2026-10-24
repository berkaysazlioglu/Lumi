import SwiftUI
import UIKit
import LumiMobileKit

/// Lumi colors for the phone. Three looks: light (system colors), dark
/// (system black) and Lumi (the Mac's navy/purple surfaces — Projects panel
/// `bgSurface` #12121F). Every color is a dynamic `UIColor` resolved from the
/// interface style plus the `isLumiTheme` trait, so it follows the user's
/// Appearance choice on its own.
enum LumiPalette {
    // Mac `Theme` hex values (LumiUI/Theme/Theme.swift).
    private static let bgDeepHex: UInt32 = 0x0A0A12
    private static let bgSurfaceHex: UInt32 = 0x12121F
    private static let bgElevatedHex: UInt32 = 0x1A1A2E
    private static let borderHex: UInt32 = 0x2A2A4A
    private static let textPrimaryHex: UInt32 = 0xE2E2F0
    private static let textSecondaryHex: UInt32 = 0x8888A8
    private static let accentDarkHex: UInt32 = 0xA78BFA
    /// Darker violet so the accent stays readable on white.
    private static let accentLightHex: UInt32 = 0x7C3AED

    static let uiBackground = themed(light: .systemBackground, dark: .systemBackground, lumi: bgSurfaceHex)
    static let uiElevated = themed(light: .secondarySystemBackground, dark: .secondarySystemBackground,
                                   lumi: bgElevatedHex)
    static let uiDeep = themed(light: .systemGroupedBackground, dark: .black, lumi: bgDeepHex)
    static let uiBorder = themed(light: .separator, dark: .separator, lumi: borderHex)
    static let uiTextPrimary = themed(light: .label, dark: .label, lumi: textPrimaryHex)
    static let uiTextSecondary = themed(light: .secondaryLabel, dark: .secondaryLabel, lumi: textSecondaryHex)
    static let uiAccent = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: accentDarkHex) : UIColor(hex: accentLightHex) }

    static let background = Color(uiBackground)
    static let elevated = Color(uiElevated)
    static let deep = Color(uiDeep)
    static let border = Color(uiBorder)
    static let textPrimary = Color(uiTextPrimary)
    static let textSecondary = Color(uiTextSecondary)
    static let accent = Color(uiAccent)

    /// Mac project palette (`Theme.ProjectTint.Hex`, decision 120).
    static func projectColor(_ id: ProjectColorID) -> Color {
        Color(UIColor(hex: projectHex(id)))
    }

    private static func projectHex(_ id: ProjectColorID) -> UInt32 {
        switch id {
        case .blue: 0x60A5FA
        case .teal: 0x2DD4BF
        case .pink: 0xF472B6
        case .orange: 0xFB923C
        case .lime: 0xA3E635
        case .green: 0x4ADE80
        case .fuchsia: 0xE879F9
        }
    }

    /// Light / dark (black) / Lumi (navy) variants of one color.
    static func themed(light: UIColor, dark: UIColor, lumi hex: UInt32) -> UIColor {
        UIColor { traits in
            guard traits.userInterfaceStyle == .dark else { return light.resolvedColor(with: traits) }
            return traits.isLumiTheme ? UIColor(hex: hex) : dark.resolvedColor(with: traits)
        }
    }

    static func themed(light: UInt32, dark: UInt32, lumi: UInt32) -> UIColor {
        themed(light: UIColor(hex: light), dark: UIColor(hex: dark), lumi: lumi)
    }
}

/// User-chosen appearance (Settings menu). `system` follows the phone with
/// light and dark (black); Lumi is the navy theme and the default.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark, lumi

    static let storageKey = "appearanceMode"
    static let `default` = AppearanceMode.lumi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        case .lumi: "Lumi"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark, .lumi: .dark
        }
    }

    var isLumi: Bool { self == .lumi }
}

/// Custom trait (iOS 17): "the Lumi navy theme is on". Bridged to SwiftUI's
/// environment so dynamic `UIColor`s in both worlds resolve with it.
struct LumiThemeTrait: UITraitDefinition {
    static let defaultValue = false
    static let affectsColorAppearance = true
}

extension UITraitCollection {
    var isLumiTheme: Bool { self[LumiThemeTrait.self] }
}

extension UIMutableTraits {
    var isLumiTheme: Bool {
        get { self[LumiThemeTrait.self] }
        set { self[LumiThemeTrait.self] = newValue }
    }
}

struct LumiThemeKey: EnvironmentKey {
    static let defaultValue = false
}

extension LumiThemeKey: UITraitBridgedEnvironmentKey {
    static func read(from traitCollection: UITraitCollection) -> Bool { traitCollection.isLumiTheme }
    static func write(to mutableTraits: inout UIMutableTraits, value: Bool) { mutableTraits.isLumiTheme = value }
}

extension EnvironmentValues {
    var isLumiTheme: Bool {
        get { self[LumiThemeKey.self] }
        set { self[LumiThemeKey.self] = newValue }
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// Text field on the Lumi surfaces (replaces `.roundedBorder`, whose white /
/// black fill ignores the palette).
private struct LumiFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(LumiPalette.elevated, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(LumiPalette.border, lineWidth: 1))
    }
}

extension View {
    func lumiField() -> some View { modifier(LumiFieldModifier()) }
}
