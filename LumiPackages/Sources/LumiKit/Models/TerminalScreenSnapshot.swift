import Foundation

/// Aynı stile sahip ardışık hücre koşusu — remote dashboard'un stilli ekran
/// payload'ı (design/06 §2). JSON anahtarları payload boyutu için kısadır.
public struct TerminalScreenRun: Sendable, Equatable, Codable {
    /// Koşu metni; hiç yazılmamış (null) hücreler boşluğa çevrilmiş halde.
    public let text: String
    /// CSS rengi ("#rrggbb"); nil = temanın default ön/arka plan rengi.
    public let foreground: String?
    public let background: String?
    /// `TerminalRunFlag` bitmask'i; 0 = düz metin.
    public let flags: Int

    public init(text: String, foreground: String? = nil, background: String? = nil, flags: Int = 0) {
        self.text = text
        self.foreground = foreground
        self.background = background
        self.flags = flags
    }

    enum CodingKeys: String, CodingKey {
        case text = "t"
        case foreground = "fg"
        case background = "bg"
        case flags = "f"
    }
}

/// `TerminalScreenRun.flags` bit değerleri (client'taki render ile sözleşme).
public enum TerminalRunFlag {
    public static let bold = 1
    public static let italic = 2
    public static let underline = 4
    public static let dim = 8
    public static let strikethrough = 16
}

/// Emülatör buffer'ının iki parçalı anlık görüntüsü: scrollback kuyruğu düz
/// metin (hacim), görünür ekran stilli koşular (Claude Code'un canlı TUI'si).
public struct TerminalScreenSnapshot: Sendable, Equatable {
    public let history: String
    /// Görünür ekranın satırları; her satır stil koşularına bölünmüş.
    public let screen: [[TerminalScreenRun]]

    public init(history: String, screen: [[TerminalScreenRun]]) {
        self.history = history
        self.screen = screen
    }
}
