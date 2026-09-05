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

    /// Dosya türü ikon paleti (Explorer). Tonlar VS Code / GitHub Linguist
    /// dil renklerinden alınır, ama koyu zeminde (bgSurface #12121F) okunur
    /// kalacak biçimde seçilir: C# ve YAML'ın kendi tonları bu zeminde
    /// kararıyordu, bu yüzden daha açık mora çekildi.
    ///
    /// Renkler YALNIZ burada tanımlanır; `fileColor(for:)` dışında hiçbir
    /// görünüm tür rengini kendisi kurmaz.
    public enum FileColor {
        public static let swift = Color(hex: 0xF05138)
        public static let csharp = Color(hex: 0x6FCF97)
        public static let typescript = Color(hex: 0x3178C6)
        public static let javascript = Color(hex: 0xF1E05A)
        public static let json = Color(hex: 0xCBCB41)
        public static let yaml = Color(hex: 0xA074C4)
        public static let markdown = Color(hex: 0x5B9BD5)
        public static let shell = Color(hex: 0x89E051)
        public static let python = Color(hex: 0x3572A5)
        public static let image = Color(hex: 0xA074C4)
        public static let shader = Color(hex: 0x4EC9B0)
        /// Nötr-soğuk klasör tonu: VS Code'un sarısı Lumi'nin mor/lacivert
        /// paletinde yabancı duruyordu.
        public static let folder = Color(hex: 0x9AA7C7)
        /// Unity ikonları PNG olarak gelir; bu ton yalnız SF Symbol fallback'i.
        public static let unity = Color(hex: 0x7FC8E8)
        public static let git = Color(hex: 0xE86A33)
        public static let lock = Color(hex: 0xD9A441)
        public static let media = Color(hex: 0x6FB3B8)
    }

    /// Dosya sınıfı → ikon rengi. Sınıflandırma LumiKit'te (`FileKind`),
    /// renklendirme burada: model renk bilmez.
    public static func fileColor(for kind: FileKind) -> Color {
        switch kind {
        case .folder, .folderOpen: return FileColor.folder
        case .swift: return FileColor.swift
        case .csharp: return FileColor.csharp
        case .typescript: return FileColor.typescript
        case .javascript: return FileColor.javascript
        case .json: return FileColor.json
        case .yaml: return FileColor.yaml
        case .markdown: return FileColor.markdown
        case .shell: return FileColor.shell
        case .python: return FileColor.python
        case .image: return FileColor.image
        case .shader: return FileColor.shader
        case .unityScene, .unityPrefab, .unityScriptableObject, .unityMaterial:
            return FileColor.unity
        case .git: return FileColor.git
        case .lock: return FileColor.lock
        case .audio, .video: return FileColor.media
        case .unityMeta: return textMuted
        case .config, .text, .archive, .font, .generic: return textSecondary
        }
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
