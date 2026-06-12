import Foundation

/// Tema picker'ı için hafif UI metadata'sı (id + ad + önizleme renk hex'leri).
///
/// Tam tema tanımları (ANSI palet, NSColor üretimi, SwiftTerm apply) LumiTerminal'de
/// `TerminalTheme`'de yaşar; LumiUI o modülü import etmediğinden picker'ın ihtiyacı
/// olan sadeleştirilmiş katalog burada tutulur. id'ler iki taraf arasında birebir
/// aynıdır — `TerminalThemeCatalogParityTests` (LumiTerminal) drift'i engeller.
public struct TerminalThemeOption: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// background, foreground, cursor + ilk 6 ANSI rengi (0xRRGGBB) — swatch şeridi.
    public let previewHex: [UInt32]

    public init(id: String, name: String, previewHex: [UInt32]) {
        self.id = id
        self.name = name
        self.previewHex = previewHex
    }
}

/// Settings tema picker'ının veri kaynağı. Sıra `TerminalTheme.all` ile aynıdır
/// (lumi önce). Renkler önizleme amaçlı; otorite LumiTerminal'dedir.
public enum TerminalThemeCatalog {
    public static let all: [TerminalThemeOption] = [
        .init(id: "lumi", name: "Lumi",
              previewHex: [0x12121F, 0xE2E2F0, 0xA78BFA,
                           0x0A0A12, 0xF87171, 0x4ADE80, 0xFBBF24, 0xA78BFA, 0x8B5CF6]),
        .init(id: "dracula", name: "Dracula",
              previewHex: [0x282A36, 0xF8F8F2, 0xF8F8F2,
                           0x21222C, 0xFF5555, 0x50FA7B, 0xF1FA8C, 0xBD93F9, 0xFF79C6]),
        .init(id: "one-dark", name: "One Dark",
              previewHex: [0x282C34, 0xABB2BF, 0x528BFF,
                           0x3F4451, 0xE05561, 0x8CC265, 0xD18F52, 0x4AA5F0, 0xC162DE]),
        .init(id: "nord", name: "Nord",
              previewHex: [0x2E3440, 0xD8DEE9, 0xD8DEE9,
                           0x3B4252, 0xBF616A, 0xA3BE8C, 0xEBCB8B, 0x81A1C1, 0xB48EAD]),
        .init(id: "solarized-dark", name: "Solarized Dark",
              previewHex: [0x002B36, 0x839496, 0x93A1A1,
                           0x073642, 0xDC322F, 0x859900, 0xB58900, 0x268BD2, 0xD33682]),
        .init(id: "solarized-light", name: "Solarized Light",
              previewHex: [0xFDF6E3, 0x657B83, 0x586E75,
                           0x073642, 0xDC322F, 0x859900, 0xB58900, 0x268BD2, 0xD33682]),
        .init(id: "github-light", name: "GitHub Light",
              previewHex: [0xFFFFFF, 0x586069, 0x005CC5,
                           0x24292E, 0xD73A49, 0x28A745, 0xDBAB09, 0x0366D6, 0x5A32A3]),
    ]
}
