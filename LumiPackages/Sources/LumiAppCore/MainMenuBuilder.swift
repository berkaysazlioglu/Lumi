import AppKit
import LumiKit

/// Ana menü — kısayolların TEK kaynağı olan `AppCommands.all` tablosundan
/// kurulur (design/03 §2, refactor 3.5). SwiftUI `.keyboardShortcut` ve
/// `keyDown` handler'ı hiçbir yerde kullanılmaz.
///
/// Uygulamaya özgü item'lar `MenuActionDispatcher`'a, platform standardı
/// item'lar (Edit ▸ Cut/Copy/Paste/Select All, Window ▸ Minimize, Quit)
/// responder chain'e gider.
@MainActor
enum MainMenuBuilder {
    /// Kurulmuş menü ağacı — `install` bunu `NSApp`'e bağlar, testler doğrudan
    /// gezer (menü kurulumu NSApp'ten bağımsız kalır).
    struct Menus {
        let mainMenu: NSMenu
        let windowMenu: NSMenu
    }

    /// Responder chain'e giden standart selector'lar. Tablodaki komut kimliği
    /// burada varsa item hedefsiz kurulur.
    private static let standardSelectors: [CommandID: Selector] = [
        .cut: #selector(NSText.cut(_:)),
        .copy: #selector(NSText.copy(_:)),
        .paste: #selector(NSText.paste(_:)),
        .selectAll: #selector(NSText.selectAll(_:)),
        .minimizeWindow: #selector(NSWindow.miniaturize(_:)),
        .quit: #selector(NSApplication.terminate(_:)),
    ]

    static func install(dispatcher: MenuActionDispatcher) {
        let menus = build(dispatcher: dispatcher)
        NSApp.mainMenu = menus.mainMenu
        NSApp.windowsMenu = menus.windowMenu
    }

    static func build(dispatcher: MenuActionDispatcher) -> Menus {
        let mainMenu = NSMenu()
        var windowMenu: NSMenu?

        for section in MenuSection.allCases {
            let commands = AppCommands.commands(in: section)
            guard !commands.isEmpty else { continue }
            let submenu = NSMenu(title: section.title)
            for command in commands {
                if command.separatorBefore {
                    submenu.addItem(.separator())
                }
                for item in items(for: command, dispatcher: dispatcher) {
                    submenu.addItem(item)
                }
            }
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
            if section == .window { windowMenu = submenu }
        }

        return Menus(mainMenu: mainMenu, windowMenu: windowMenu ?? NSMenu(title: "Window"))
    }

    // MARK: - Item üretimi

    private static func items(
        for command: AppCommand,
        dispatcher: MenuActionDispatcher
    ) -> [NSMenuItem] {
        guard let range = command.indexRange else {
            return [item(for: command, title: command.title, key: command.key ?? "",
                         tag: 0, dispatcher: dispatcher)]
        }
        return range.map { index in
            item(
                for: command,
                title: "\(command.title) \(index)",
                key: String(index),
                tag: index,
                dispatcher: dispatcher
            )
        }
    }

    private static func item(
        for command: AppCommand,
        title: String,
        key: String,
        tag: Int,
        dispatcher: MenuActionDispatcher
    ) -> NSMenuItem {
        let selector = standardSelectors[command.id]
        let item = NSMenuItem(
            title: title,
            action: selector ?? #selector(MenuActionDispatcher.performCommand(_:)),
            keyEquivalent: key
        )
        item.keyEquivalentModifierMask = modifierFlags(command.modifiers)
        item.tag = tag
        if selector == nil {
            item.target = dispatcher
            item.representedObject = command.id.rawValue
        }
        return item
    }

    private static func modifierFlags(_ modifiers: CommandModifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        return flags
    }
}
