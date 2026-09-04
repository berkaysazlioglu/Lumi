import LumiKit

/// Settings → Shortcuts sekmesinin salt-okunur kısayol referansı.
///
/// Refactor 3.5: liste artık ELLE tutulmuyor — kısayolların tek kaynağı olan
/// `LumiKit.AppCommands.all` tablosundan türetilir. `MainMenuBuilder` de aynı
/// tablodan menüyü kurduğu için iki taraf yapısal olarak ayrışamaz.
public struct ShortcutReference: Sendable, Identifiable, Equatable {
    public let action: String
    /// Bir aksiyonun bir ya da daha çok kombosu (ör. "⌘1 – ⌘9" iki kombo).
    public let combos: [[String]]

    public var id: String { action }

    public init(action: String, combos: [[String]]) {
        self.action = action
        self.combos = combos
    }

    /// Kullanıcıya gösterilen kısayol tablosu (platform standardı Edit/Window
    /// item'ları bilinçli olarak dışarıdadır — design/03 §2).
    public static let all: [ShortcutReference] = AppCommands.reference.map {
        ShortcutReference(action: $0.referenceTitle ?? $0.title, combos: $0.displayCombos)
    }
}
