import AppKit

/// Ana menü — kısayolların TEK kaynağı (design/03 §2): Cmd+T/W/O/,/1-9/
/// Shift+oklar/Shift+F. SwiftUI .keyboardShortcut hiçbir yerde kullanılmaz.
/// Edit menüsü terminal copy-paste için zorunludur (spec/30).
@MainActor
enum MainMenuBuilder {
    struct Actions {
        let target: AnyObject
        let newTerminal: Selector
        let closeTerminal: Selector
        let openRepoSelector: Selector
        let focusNext: Selector
        let focusPrevious: Selector
        let focusIndex: Selector // sender.tag = 1-9
        let toggleLeftSidebar: Selector
        let toggleRightSidebar: Selector
        let openSettings: Selector
        let toggleFocusMode: Selector
    }

    static func install(actions: Actions) {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(targeted(
            title: "Settings…", action: actions.openSettings,
            key: ",", target: actions.target
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Lumi",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let shellItem = NSMenuItem()
        let shellMenu = NSMenu(title: "Shell")
        shellMenu.addItem(targeted(
            title: "New Terminal", action: actions.newTerminal,
            key: "t", target: actions.target
        ))
        // Cmd+W terminali kapatır, pencereyi DEĞİL (design/03 §2)
        shellMenu.addItem(targeted(
            title: "Close Terminal", action: actions.closeTerminal,
            key: "w", target: actions.target
        ))
        shellMenu.addItem(.separator())
        shellMenu.addItem(targeted(
            title: "Open Repo…", action: actions.openRepoSelector,
            key: "o", target: actions.target
        ))
        shellItem.submenu = shellMenu
        mainMenu.addItem(shellItem)

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

        let terminalItem = NSMenuItem()
        let terminalMenu = NSMenu(title: "Terminal")
        let nextItem = targeted(
            title: "Next Terminal", action: actions.focusNext,
            key: String(UnicodeScalar(NSRightArrowFunctionKey)!), target: actions.target
        )
        nextItem.keyEquivalentModifierMask = [.command, .shift]
        terminalMenu.addItem(nextItem)
        let previousItem = targeted(
            title: "Previous Terminal", action: actions.focusPrevious,
            key: String(UnicodeScalar(NSLeftArrowFunctionKey)!), target: actions.target
        )
        previousItem.keyEquivalentModifierMask = [.command, .shift]
        terminalMenu.addItem(previousItem)
        terminalMenu.addItem(.separator())
        for index in 1...9 {
            let item = targeted(
                title: "Terminal \(index)", action: actions.focusIndex,
                key: "\(index)", target: actions.target
            )
            item.tag = index
            terminalMenu.addItem(item)
        }
        terminalItem.submenu = terminalMenu
        mainMenu.addItem(terminalItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(targeted(
            title: "Toggle Left Sidebar", action: actions.toggleLeftSidebar,
            key: "b", target: actions.target
        ))
        let rightSidebarItem = targeted(
            title: "Toggle Right Sidebar", action: actions.toggleRightSidebar,
            key: "B", target: actions.target
        )
        rightSidebarItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(rightSidebarItem)
        viewMenu.addItem(.separator())
        let focusModeItem = targeted(
            title: "Toggle Focus Mode", action: actions.toggleFocusMode,
            key: "F", target: actions.target
        )
        focusModeItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(focusModeItem)
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

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

    private static func targeted(
        title: String,
        action: Selector,
        key: String,
        target: AnyObject
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }
}
