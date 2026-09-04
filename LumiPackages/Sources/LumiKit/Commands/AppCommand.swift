import Foundation

/// Uygulama komutunun kimliği. Menü item'ı, dispatcher handler'ı ve kısayol
/// referansı bu kimlikle eşleşir (refactor 3.5).
public struct CommandID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}

public extension CommandID {
    static let openSettings: CommandID = "openSettings"
    static let quit: CommandID = "quit"
    static let newTerminal: CommandID = "newTerminal"
    static let closeTerminal: CommandID = "closeTerminal"
    static let openRepoSelector: CommandID = "openRepoSelector"
    static let cut: CommandID = "cut"
    static let copy: CommandID = "copy"
    static let paste: CommandID = "paste"
    static let selectAll: CommandID = "selectAll"
    static let focusNextTerminal: CommandID = "focusNextTerminal"
    static let focusPreviousTerminal: CommandID = "focusPreviousTerminal"
    static let focusTerminalAtIndex: CommandID = "focusTerminalAtIndex"
    static let toggleMaximizeTerminal: CommandID = "toggleMaximizeTerminal"
    static let toggleLeftSidebar: CommandID = "toggleLeftSidebar"
    static let toggleRightSidebar: CommandID = "toggleRightSidebar"
    static let toggleFocusMode: CommandID = "toggleFocusMode"
    static let minimizeWindow: CommandID = "minimizeWindow"
}

/// Kısayol değiştiricileri — AppKit'ten bağımsız (LumiKit AppKit görmez).
/// `NSEvent.ModifierFlags` eşlemesi menü kurucusundadır.
public struct CommandModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = CommandModifiers(rawValue: 1 << 0)
    public static let shift = CommandModifiers(rawValue: 1 << 1)
    public static let option = CommandModifiers(rawValue: 1 << 2)
    public static let control = CommandModifiers(rawValue: 1 << 3)
}

/// Ana menüdeki bölümler (sıralama menü çubuğu sırasıdır).
public enum MenuSection: String, Sendable, CaseIterable {
    case app
    case shell
    case edit
    case terminal
    case view
    case window

    /// `NSMenu.title`. Uygulama menüsünün başlığı boştur (AppKit onu uygulama
    /// adıyla doldurur).
    public var title: String {
        switch self {
        case .app: return ""
        case .shell: return "Shell"
        case .edit: return "Edit"
        case .terminal: return "Terminal"
        case .view: return "View"
        case .window: return "Window"
        }
    }
}

/// Fonksiyon tuşlarının Unicode karşılıkları. `NSLeftArrowFunctionKey` ve
/// kardeşleri AppKit sabitleri olsa da değerleri Unicode private-use
/// alanındadır; LumiKit'te AppKit'siz tanımlanabilirler.
public enum CommandKey {
    public static let leftArrow = String(UnicodeScalar(0xF702)!)
    public static let rightArrow = String(UnicodeScalar(0xF703)!)
}

/// Bir uygulama komutunun TEK kaynağı (refactor 3.5): menü item'ı, kısayol,
/// dispatcher kaydı ve Settings ▸ Shortcuts satırı buradan türer.
public struct AppCommand: Identifiable, Sendable, Equatable {
    public let id: CommandID
    /// Menüde görünen başlık. İndeksli komutlarda taban başlık ("Terminal").
    public let title: String
    public let menu: MenuSection
    /// `NSMenuItem.keyEquivalent`. İndeksli komutlarda `nil` — tuş indeksten türer.
    public let key: String?
    public let modifiers: CommandModifiers
    /// Platform standardı (Edit ▸ Cut/Copy/Paste/Select All, Window ▸ Minimize):
    /// responder chain'e gider, uygulamanın dispatcher'ına bağlanmaz ve
    /// Shortcuts tablosunda listelenmez (design/03 §2).
    public let isSystemStandard: Bool
    /// Menüde bu item'dan önce ayraç.
    public let separatorBefore: Bool
    /// ⌘1…⌘9 gibi indeksli aile: aralıktaki her değer için ayrı menü item'ı
    /// üretilir (`tag` = indeks).
    public let indexRange: ClosedRange<Int>?
    /// Settings ▸ Shortcuts tablosundaki etiket; `nil` ise tabloda görünmez.
    /// Menü başlığından farklı olabilir ("Open Repo…" → "Open Repository").
    public let referenceTitle: String?
    /// Shortcuts tablosundaki sıra. Menü sırasından bağımsızdır: kullanıcıya
    /// gösterilen sıralama menü ağacı yeniden düzenlense de sabit kalır.
    public let referenceOrder: Int?

    public init(
        id: CommandID,
        title: String,
        menu: MenuSection,
        key: String?,
        modifiers: CommandModifiers = .command,
        isSystemStandard: Bool = false,
        separatorBefore: Bool = false,
        indexRange: ClosedRange<Int>? = nil,
        referenceTitle: String? = nil,
        referenceOrder: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.menu = menu
        self.key = key
        self.modifiers = modifiers
        self.isSystemStandard = isSystemStandard
        self.separatorBefore = separatorBefore
        self.indexRange = indexRange
        self.referenceTitle = referenceTitle
        self.referenceOrder = referenceOrder
    }

    /// Kullanıcıya gösterilen kombo(lar). İndeksli komut iki uç kombo ile
    /// ifade edilir ("⌘1 – ⌘9"), tekil komut tek kombo.
    public var displayCombos: [[String]] {
        if let indexRange {
            return [
                Self.symbols(modifiers) + [String(indexRange.lowerBound)],
                Self.symbols(modifiers) + [String(indexRange.upperBound)],
            ]
        }
        guard let key else { return [] }
        return [Self.symbols(modifiers) + [Self.keySymbol(key)]]
    }

    /// Sembol sırası: ⌘, ⌃, ⌥, ⇧, sonra tuş.
    public static func symbols(_ modifiers: CommandModifiers) -> [String] {
        var result: [String] = []
        if modifiers.contains(.command) { result.append("⌘") }
        if modifiers.contains(.control) { result.append("⌃") }
        if modifiers.contains(.option) { result.append("⌥") }
        if modifiers.contains(.shift) { result.append("⇧") }
        return result
    }

    public static func keySymbol(_ key: String) -> String {
        switch key {
        case CommandKey.leftArrow: return "←"
        case CommandKey.rightArrow: return "→"
        default: return key.uppercased()
        }
    }
}
