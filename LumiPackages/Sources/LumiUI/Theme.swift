import LumiKit
import SwiftUI

/// Lumi görsel kimliğinin token katmanı (karar 13, spec/23) — Faz 1 alt kümesi.
/// Tam ölçek (tipografi, motion, component stilleri) Faz 6'da tamamlanır.
public enum Theme {
    public static let bgDeep = Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x12 / 255)
    public static let bgSurface = Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x1F / 255)
    public static let bgElevated = Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x2E / 255)

    public static let textPrimary = Color(red: 0xE2 / 255, green: 0xE2 / 255, blue: 0xF0 / 255)
    public static let textSecondary = Color(red: 0x88 / 255, green: 0x88 / 255, blue: 0xA8 / 255)
    public static let textMuted = Color(red: 0x4A / 255, green: 0x4A / 255, blue: 0x6A / 255)

    public static let accentPrimary = Color(red: 0xA7 / 255, green: 0x8B / 255, blue: 0xFA / 255)
    public static let accentVivid = Color(red: 0x8B / 255, green: 0x5C / 255, blue: 0xF6 / 255)
    public static let success = Color(red: 0x4A / 255, green: 0xDE / 255, blue: 0x80 / 255)
    public static let warning = Color(red: 0xFB / 255, green: 0xBF / 255, blue: 0x24 / 255)
    public static let error = Color(red: 0xF8 / 255, green: 0x71 / 255, blue: 0x71 / 255)
    public static let border = Color(red: 0x2A / 255, green: 0x2A / 255, blue: 0x4A / 255)

    /// StatusDot renk sistemi (spec/23): durum → renk eşlemesi birebir.
    public static func statusColor(for status: TerminalStatus) -> Color {
        switch status {
        case .idle: return textMuted
        case .working: return success
        case .waitingUnseen: return warning
        case .waitingFocused: return textMuted
        case .waitingSeen: return warning
        case .error: return error
        }
    }
}
