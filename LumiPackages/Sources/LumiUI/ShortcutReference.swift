/// Settings → Shortcuts sekmesinin salt-okunur kısayol referansı (spec/22 §5.6).
///
/// Kısayolların ÇALIŞAN tek kaynağı `MainMenuBuilder`'dır (LumiApp); bu liste
/// onun görsel aynasıdır. LumiUI, LumiApp'i (executable) göremediğinden veri
/// burada elle tutulur — menüye kısayol ekleyince bu tabloyu da güncelle.
public struct ShortcutReference: Sendable, Identifiable, Equatable {
    public let action: String
    /// Bir aksiyonun bir ya da daha çok kombosu (ör. "⌘1 – ⌘9" iki kombo).
    public let combos: [[String]]

    public var id: String { action }

    public init(action: String, combos: [[String]]) {
        self.action = action
        self.combos = combos
    }

    /// Menüdeki gerçek kısayolların sırası (MainMenuBuilder ile birebir).
    public static let all: [ShortcutReference] = [
        ShortcutReference(action: "New Terminal", combos: [["⌘", "T"]]),
        ShortcutReference(action: "Close Terminal", combos: [["⌘", "W"]]),
        ShortcutReference(action: "Open Repository", combos: [["⌘", "O"]]),
        ShortcutReference(action: "Switch to Tab N", combos: [["⌘", "1"], ["⌘", "9"]]),
        ShortcutReference(action: "Previous Terminal", combos: [["⌘", "⇧", "←"]]),
        ShortcutReference(action: "Next Terminal", combos: [["⌘", "⇧", "→"]]),
        ShortcutReference(action: "Maximize Terminal", combos: [["⌘", "⌃", "M"]]),
        ShortcutReference(action: "Toggle Left Sidebar", combos: [["⌘", "B"]]),
        ShortcutReference(action: "Toggle Right Sidebar", combos: [["⌘", "⇧", "B"]]),
        ShortcutReference(action: "Focus Mode", combos: [["⌘", "⇧", "F"]]),
        ShortcutReference(action: "Settings", combos: [["⌘", ","]]),
        ShortcutReference(action: "Quit", combos: [["⌘", "Q"]]),
    ]
}
