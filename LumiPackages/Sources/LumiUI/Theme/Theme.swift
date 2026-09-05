import AppKit
import LumiKit
import SwiftUI

/// Lumi görsel kimliğinin token katmanı (karar 13) — Faz 1 alt kümesi.
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
    /// Commit butonu hover'ı (v1 --accent-primary-deep #7C3AED).
    public static let accentDeep = Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255)
    public static let accentCyan = Color(red: 0x22 / 255, green: 0xD3 / 255, blue: 0xEE / 255)
    public static let success = Color(red: 0x4A / 255, green: 0xDE / 255, blue: 0x80 / 255)
    public static let warning = Color(red: 0xFB / 255, green: 0xBF / 255, blue: 0x24 / 255)
    public static let error = Color(red: 0xF8 / 255, green: 0x71 / 255, blue: 0x71 / 255)
    public static let border = Color(red: 0x2A / 255, green: 0x2A / 255, blue: 0x4A / 255)

    /// Git decoration paleti (VS Code SCM renkleri; Explorer badge + Source Control).
    public static let gitModified = Color(hex: 0xE2C08D)
    public static let gitAdded = Color(hex: 0x81B88B)
    public static let gitDeleted = Color(hex: 0xC74E39)
    public static let gitUntracked = Color(hex: 0x73C991)

    /// NSAttributedString tabanlı görünümler (FileViewer/diff) için AppKit renkleri.
    public enum NS {
        public static let bgDeep = NSColor(srgbRed: 0x0A / 255, green: 0x0A / 255, blue: 0x12 / 255, alpha: 1)
        public static let bgElevated = NSColor(srgbRed: 0x1A / 255, green: 0x1A / 255, blue: 0x2E / 255, alpha: 1)
        public static let textPrimary = NSColor(srgbRed: 0xE2 / 255, green: 0xE2 / 255, blue: 0xF0 / 255, alpha: 1)
        public static let textMuted = NSColor(srgbRed: 0x4A / 255, green: 0x4A / 255, blue: 0x6A / 255, alpha: 1)
        public static let cyan = NSColor(srgbRed: 0x22 / 255, green: 0xD3 / 255, blue: 0xEE / 255, alpha: 1)
        public static let success = NSColor(srgbRed: 0x4A / 255, green: 0xDE / 255, blue: 0x80 / 255, alpha: 1)
        public static let error = NSColor(srgbRed: 0xF8 / 255, green: 0x71 / 255, blue: 0x71 / 255, alpha: 1)
        // Diff zeminleri `Theme+Diff.swift`'te (refactor 7.9: tek kaynak).
    }

    /// Git status rozet rengi — tek kaynak (Explorer/SourceControl palet
    /// tutarsızlığı taşınmaz, karar 11). VS Code SCM decoration renkleri.
    public static func fileChangeColor(for status: FileChangeStatus) -> Color {
        switch status {
        case .modified: return gitModified
        case .added: return gitAdded
        case .deleted: return gitDeleted
        case .renamed, .untracked: return gitUntracked
        }
    }

    /// StatusDot renk sistemi: durum → renk eşlemesi birebir.
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

extension Color {
    /// 0xRRGGBB hex → opak SwiftUI Color (terminal tema swatch önizlemeleri).
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
