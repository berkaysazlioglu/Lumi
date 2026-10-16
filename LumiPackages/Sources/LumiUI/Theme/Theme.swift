import AppKit
import LumiKit
import SwiftUI

/// Lumi görsel kimliğinin token katmanı (karar 13) — Faz 1 alt kümesi.
/// Tam ölçek (tipografi, motion, component stilleri) Faz 6'da tamamlanır.
public enum Theme {
    public static let bgDeep = Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x12 / 255)
    public static let bgSurface = Color(hex: Hex.bgSurface)
    public static let bgElevated = Color(hex: Hex.bgElevated)

    public static let textPrimary = Color(hex: Hex.textPrimary)
    public static let textSecondary = Color(hex: Hex.textSecondary)
    public static let textMuted = Color(red: 0x4A / 255, green: 0x4A / 255, blue: 0x6A / 255)

    public static let accentPrimary = Color(red: 0xA7 / 255, green: 0x8B / 255, blue: 0xFA / 255)
    public static let accentVivid = Color(red: 0x8B / 255, green: 0x5C / 255, blue: 0xF6 / 255)
    /// Commit butonu hover'ı (v1 --accent-primary-deep #7C3AED).
    public static let accentDeep = Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255)
    public static let accentCyan = Color(red: 0x22 / 255, green: 0xD3 / 255, blue: 0xEE / 255)
    /// Durum paletinin HAM değerleri. `Color` bileşenlerini geri vermediği için
    /// rampanın (`Theme.blend`) ara ton üretebilmesi hex'e ihtiyaç duyar;
    /// renkler yine tek yerde, burada tanımlanır.
    public enum Hex {
        public static let success: UInt32 = 0x4ADE80
        public static let warning: UInt32 = 0xFBBF24
        public static let error: UInt32 = 0xF87171
        /// Tempo rampasının soğuk ucu (karar 85).
        public static let ice: UInt32 = 0x38BDF8
        /// Zemin ve metin tonları — proje rengi ara tonları (karar 120) ve
        /// kontrast testleri bileşen ister.
        public static let bgSurface: UInt32 = 0x12121F
        public static let bgElevated: UInt32 = 0x1A1A2E
        public static let textPrimary: UInt32 = 0xE2E2F0
        public static let textSecondary: UInt32 = 0x8888A8
    }

    public static let success = Color(hex: Hex.success)
    public static let warning = Color(hex: Hex.warning)
    public static let error = Color(hex: Hex.error)
    /// Buz mavisi: limitin gerisinde kalan, yani rahat olan kullanım (karar 85).
    /// Yeşille aynı "iyi" ailesindedir ama farklı bir şey söyler — yeşil
    /// "tempoda", buz mavisi "tempodan yavaş" demektir.
    public static let ice = Color(hex: Hex.ice)
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

    /// İki palet rengi arasında sRGB ara tonu (`t` = 0 → `a`, 1 → `b`).
    ///
    /// Renk rampaları için vardır (karar 85): ara ton bir TOKEN DEĞİLDİR, iki
    /// token arasındaki ölçülmüş konumdur — bu yüzden çağıran hex sabitlerini
    /// verir, kendi rengini kurmaz.
    public static func blend(_ a: UInt32, _ b: UInt32, _ t: Double) -> Color {
        let t = min(1, max(0, t))
        func channel(_ shift: UInt32) -> Double {
            let from = Double((a >> shift) & 0xFF)
            let to = Double((b >> shift) & 0xFF)
            return (from + (to - from) * t) / 255
        }
        return Color(.sRGB, red: channel(16), green: channel(8), blue: channel(0), opacity: 1)
    }

    /// Kompakt terminal chip'lerinin durum noktası renk sistemi.
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
