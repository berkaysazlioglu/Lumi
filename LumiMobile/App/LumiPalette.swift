import SwiftUI
import UIKit
import LumiMobileKit

/// Lumi colors for the phone. Two looks: light (system colors) and dark —
/// the Mac's navy/purple surfaces (Projects panel `bgSurface` #12121F).
/// Every color is a dynamic `UIColor` resolved from the interface style, so
/// it follows the user's Appearance choice on its own.
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

    static let uiBackground = themed(light: .systemBackground, dark: bgSurfaceHex)
    static let uiElevated = themed(light: .secondarySystemBackground, dark: bgElevatedHex)
    static let uiDeep = themed(light: .systemGroupedBackground, dark: bgDeepHex)
    static let uiBorder = themed(light: .separator, dark: borderHex)
    static let uiTextPrimary = themed(light: .label, dark: textPrimaryHex)
    static let uiTextSecondary = themed(light: .secondaryLabel, dark: textSecondaryHex)
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

    /// Light / dark (Lumi navy) variants of one color.
    static func themed(light: UIColor, dark hex: UInt32) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: hex) : light.resolvedColor(with: traits)
        }
    }

    static func themed(light: UInt32, dark: UInt32) -> UIColor {
        themed(light: UIColor(hex: light), dark: dark)
    }
}

/// User-chosen appearance (Settings). Dark is Lumi's navy look — the former
/// separate black "Dark" and navy "Lumi" modes were one look in practice and
/// became one (decision 134). A stored `lumi` no longer decodes and falls
/// back to the default, which is dark — the same look.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearanceMode"
    static let `default` = AppearanceMode.dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
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
