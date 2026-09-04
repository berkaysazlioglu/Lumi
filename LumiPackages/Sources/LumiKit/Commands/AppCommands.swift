import Foundation

/// Uygulamanın komut tablosu — kısayolların TEK kaynağı (design/03 §2,
/// refactor 3.5). `MainMenuBuilder` menüyü, `MenuActionDispatcher` handler
/// kaydını, `ShortcutReference` Settings tablosunu BURADAN üretir.
///
/// Yeni komut eklemek = bu tabloya bir satır + dispatcher'da bir handler.
public enum AppCommands {
    public static let all: [AppCommand] = [
        // MARK: App
        AppCommand(
            id: .openSettings, title: "Settings…", menu: .app, key: ",",
            referenceTitle: "Settings", referenceOrder: 11
        ),
        // Standart `NSApplication.terminate(_:)` selector'ına gider ama
        // kullanıcıya sunulan tabloda listelenir.
        AppCommand(
            id: .quit, title: "Quit Lumi", menu: .app, key: "q",
            separatorBefore: true, referenceTitle: "Quit", referenceOrder: 12
        ),

        // MARK: Shell
        AppCommand(
            id: .newTerminal, title: "New Terminal", menu: .shell, key: "t",
            referenceTitle: "New Terminal", referenceOrder: 1
        ),
        // ⌘W terminali kapatır, pencereyi DEĞİL (design/03 §2 — menü interception).
        AppCommand(
            id: .closeTerminal, title: "Close Terminal", menu: .shell, key: "w",
            referenceTitle: "Close Terminal", referenceOrder: 2
        ),
        AppCommand(
            id: .openRepoSelector, title: "Open Repo…", menu: .shell, key: "o",
            separatorBefore: true, referenceTitle: "Open Repository", referenceOrder: 3
        ),

        // MARK: Edit (terminal copy-paste için ZORUNLU, design/03 §2)
        AppCommand(id: .cut, title: "Cut", menu: .edit, key: "x", isSystemStandard: true),
        AppCommand(id: .copy, title: "Copy", menu: .edit, key: "c", isSystemStandard: true),
        AppCommand(id: .paste, title: "Paste", menu: .edit, key: "v", isSystemStandard: true),
        AppCommand(
            id: .selectAll, title: "Select All", menu: .edit, key: "a",
            isSystemStandard: true
        ),

        // MARK: Terminal
        AppCommand(
            id: .focusNextTerminal, title: "Next Terminal", menu: .terminal,
            key: CommandKey.rightArrow, modifiers: [.command, .shift],
            referenceTitle: "Next Terminal", referenceOrder: 6
        ),
        AppCommand(
            id: .focusPreviousTerminal, title: "Previous Terminal", menu: .terminal,
            key: CommandKey.leftArrow, modifiers: [.command, .shift],
            referenceTitle: "Previous Terminal", referenceOrder: 5
        ),
        AppCommand(
            id: .focusTerminalAtIndex, title: "Terminal", menu: .terminal, key: nil,
            separatorBefore: true, indexRange: 1...9,
            referenceTitle: "Switch to Tab N", referenceOrder: 4
        ),
        AppCommand(
            id: .toggleMaximizeTerminal, title: "Maximize Terminal", menu: .terminal,
            key: "m", modifiers: [.command, .control], separatorBefore: true,
            referenceTitle: "Maximize Terminal", referenceOrder: 7
        ),

        // MARK: View
        AppCommand(
            id: .toggleLeftSidebar, title: "Toggle Left Sidebar", menu: .view, key: "b",
            referenceTitle: "Toggle Left Sidebar", referenceOrder: 8
        ),
        AppCommand(
            id: .toggleRightSidebar, title: "Toggle Right Sidebar", menu: .view, key: "B",
            modifiers: [.command, .shift],
            referenceTitle: "Toggle Right Sidebar", referenceOrder: 9
        ),
        AppCommand(
            id: .toggleFocusMode, title: "Toggle Focus Mode", menu: .view, key: "F",
            modifiers: [.command, .shift], separatorBefore: true,
            referenceTitle: "Focus Mode", referenceOrder: 10
        ),

        // MARK: Window
        AppCommand(
            id: .minimizeWindow, title: "Minimize", menu: .window, key: "m",
            isSystemStandard: true
        ),
    ]

    /// Menü bölümü sırasına göre gruplanmış komutlar (tablo sırası korunur).
    public static func commands(in section: MenuSection) -> [AppCommand] {
        all.filter { $0.menu == section }
    }

    /// Settings ▸ Shortcuts tablosunun kaynağı: platform standardı olmayan,
    /// referans etiketi taşıyan komutlar, `referenceOrder` sırasında.
    public static var reference: [AppCommand] {
        all
            .filter { !$0.isSystemStandard && $0.referenceTitle != nil }
            .sorted { ($0.referenceOrder ?? .max) < ($1.referenceOrder ?? .max) }
    }
}
