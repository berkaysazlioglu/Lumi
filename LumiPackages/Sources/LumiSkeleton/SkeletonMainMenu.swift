import AppKit

/// Faz 1 minimal ana menüsü. Edit menüsü terminal copy-paste için ZORUNLUDUR
/// (spec/30): Cmd+C/V key equivalent'ları first responder'daki SwiftTerm
/// view'ının copy:/paste: selector'larına buradan yönlenir. Tam menü seti
/// (MainMenuBuilder, tek kısayol kaynağı — design/03 §2) Faz 3'te.
@MainActor
enum SkeletonMainMenu {
    static func install(closeTerminalTarget target: AnyObject, closeTerminalAction: Selector) {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit Lumi Skeleton",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        // Cmd+W terminali kapatır, pencereyi DEĞİL (design/03 §2)
        let shellItem = NSMenuItem()
        let shellMenu = NSMenu(title: "Shell")
        let closeItem = NSMenuItem(
            title: "Close Terminal",
            action: closeTerminalAction,
            keyEquivalent: "w"
        )
        closeItem.target = target
        shellMenu.addItem(closeItem)
        shellItem.submenu = shellMenu
        mainMenu.addItem(shellItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.miniaturize(_:)),
            keyEquivalent: "m"
        )
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }
}
