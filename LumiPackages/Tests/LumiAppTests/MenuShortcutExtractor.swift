import AppKit
import Foundation

/// Menü ağacındaki `keyEquivalent` + `keyEquivalentModifierMask` çiftlerini
/// `ShortcutReference`'ın sembol dizisi biçimine (ör. `["⌘", "⇧", "←"]`) çevirir.
/// İki tarafın gerçekten aynı veriyi taşıdığını kanıtlayabilmek için ortak bir
/// normal form gerekir (plan 2.7).
enum MenuShortcutExtractor {
    struct Entry: Hashable {
        let title: String
        let combo: [String]
    }

    /// Menüyü derinlemesine gezip kısayolu olan her item'ı toplar.
    static func entries(in menu: NSMenu) -> [Entry] {
        var result: [Entry] = []
        for item in menu.items {
            if !item.keyEquivalent.isEmpty {
                result.append(
                    Entry(title: item.title, combo: combo(for: item))
                )
            }
            if let submenu = item.submenu {
                result.append(contentsOf: entries(in: submenu))
            }
        }
        return result
    }

    static func combo(for item: NSMenuItem) -> [String] {
        symbols(for: item.keyEquivalentModifierMask) + [key(item.keyEquivalent)]
    }

    /// `ShortcutReference` sırası: önce ⌘, sonra diğer değiştiriciler, en sonda tuş.
    private static func symbols(for mask: NSEvent.ModifierFlags) -> [String] {
        var result: [String] = []
        if mask.contains(.command) { result.append("⌘") }
        if mask.contains(.control) { result.append("⌃") }
        if mask.contains(.option) { result.append("⌥") }
        if mask.contains(.shift) { result.append("⇧") }
        return result
    }

    private static func key(_ raw: String) -> String {
        switch raw {
        case String(UnicodeScalar(NSLeftArrowFunctionKey)!): return "←"
        case String(UnicodeScalar(NSRightArrowFunctionKey)!): return "→"
        case String(UnicodeScalar(NSUpArrowFunctionKey)!): return "↑"
        case String(UnicodeScalar(NSDownArrowFunctionKey)!): return "↓"
        default: return raw.uppercased()
        }
    }
}
