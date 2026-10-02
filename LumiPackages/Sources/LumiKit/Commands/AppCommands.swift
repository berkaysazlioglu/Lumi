import Foundation

/// Uygulamanın komut tablosu — kısayolların TEK kaynağı (design/03 §2,
/// refactor 3.5). `MainMenuBuilder` menüyü, `MenuActionDispatcher` handler
/// kaydını, `ShortcutReference` Settings tablosunu BURADAN üretir.
///
/// Yeni komut eklemek = bu tabloya bir satır + dispatcher'da bir handler.
///
/// Tablo `IndexShortcutStyle` ile parametriktir (karar 62): indeksli iki ailenin
/// (repo tab'ı / terminal) ⌘ ve ⌃ değiştiricileri ayardan gelir. Ham tablo
/// private'tır — tüketiciler `all(_:)` / `commands(in:style:)` / `reference(_:)`
/// üzerinden okur, böylece hiçbir yol düzeni atlayamaz.
public enum AppCommands {
    /// Ham tablo: indeksli komutların değiştiricileri VARSAYILAN düzendedir.
    private static let table: [AppCommand] = [
        // MARK: App
        // Karar 102: macOS'un standart About paneli yerine Settings ▸ About.
        // Kısayolu yoktur (platform geleneği) — Shortcuts tablosunda görünmez.
        AppCommand(id: .openAbout, title: "About Lumi", menu: .app, key: nil),
        AppCommand(
            id: .openSettings, title: "Settings…", menu: .app, key: ",",
            separatorBefore: true, referenceTitle: "Settings", referenceOrder: 16
        ),
        // Standart `NSApplication.terminate(_:)` selector'ına gider ama
        // kullanıcıya sunulan tabloda listelenir.
        AppCommand(
            id: .quit, title: "Quit Lumi", menu: .app, key: "q",
            separatorBefore: true, referenceTitle: "Quit", referenceOrder: 17
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
        // ⇧⌘W projeyi Projects'ten KALDIRIR (karar 66). ⌘W'ye değil ayrı bir
        // korda bağlı olması bilinçli: ⌘W refleks bir tuştur ve kaldırma hem
        // kalıcı kullanıcı verisine (`sidebarProjectPaths`) dokunur hem de
        // projenin TÜM checkout'larını kapatır — kazara basılmamalı.
        AppCommand(
            id: .closeProject, title: "Close Project", menu: .shell, key: "W",
            modifiers: [.command, .shift],
            referenceTitle: "Close Project", referenceOrder: 3
        ),
        AppCommand(
            id: .openRepoSelector, title: "Go to Project…", menu: .shell, key: "o",
            separatorBefore: true, referenceTitle: "Go to Project", referenceOrder: 4
        ),
        // ⌃1…⌃9 PROJELER arasında geçer (karar 65 — eskiden görünmeyen tab
        // listesine indeksliyordu). ⌘1…⌘9 ise aktif checkout içindeki terminali
        // odaklar; ikisi ayrı eksendir (karar 59) ve değiştiriciler ayardan
        // takas edilebilir (karar 62).
        AppCommand(
            id: .switchToProjectAtIndex, title: "Project", menu: .shell, key: nil,
            modifiers: IndexShortcutStyle.default.repoModifiers,
            separatorBefore: true, indexRange: 1...9,
            referenceTitle: "Switch to Project N", referenceOrder: 5
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
            referenceTitle: "Next Terminal", referenceOrder: 8
        ),
        AppCommand(
            id: .focusPreviousTerminal, title: "Previous Terminal", menu: .terminal,
            key: CommandKey.leftArrow, modifiers: [.command, .shift],
            referenceTitle: "Previous Terminal", referenceOrder: 7
        ),
        AppCommand(
            id: .focusTerminalAtIndex, title: "Terminal", menu: .terminal, key: nil,
            modifiers: IndexShortcutStyle.default.terminalModifiers,
            separatorBefore: true, indexRange: 1...9,
            referenceTitle: "Focus Terminal N", referenceOrder: 6
        ),
        AppCommand(
            id: .toggleMaximizeTerminal, title: "Maximize Terminal", menu: .terminal,
            key: "m", modifiers: [.command, .control], separatorBefore: true,
            referenceTitle: "Maximize Terminal", referenceOrder: 9
        ),

        // MARK: View
        AppCommand(
            id: .toggleLeftSidebar, title: "Toggle Left Sidebar", menu: .view, key: "b",
            referenceTitle: "Toggle Left Sidebar", referenceOrder: 10
        ),
        AppCommand(
            id: .toggleRightSidebar, title: "Toggle Right Sidebar", menu: .view, key: "B",
            modifiers: [.command, .shift],
            referenceTitle: "Toggle Right Sidebar", referenceOrder: 11
        ),
        AppCommand(
            id: .toggleFocusMode, title: "Toggle Focus Mode", menu: .view, key: "F",
            modifiers: [.command, .shift], separatorBefore: true,
            referenceTitle: "Focus Mode", referenceOrder: 12
        ),
        // Karar 61: tüm arayüzü ölçekler (Electron `zoomIn`/`zoomOut`/
        // `resetZoom` paritesi) — yalnız terminal fontunu değil.
        AppCommand(
            id: .zoomIn, title: "Zoom In", menu: .view, key: "+",
            separatorBefore: true, referenceTitle: "Zoom In", referenceOrder: 13
        ),
        AppCommand(
            id: .zoomOut, title: "Zoom Out", menu: .view, key: "-",
            referenceTitle: "Zoom Out", referenceOrder: 14
        ),
        AppCommand(
            id: .resetZoom, title: "Actual Size", menu: .view, key: "0",
            referenceTitle: "Actual Size", referenceOrder: 15
        ),

        // MARK: Window
        AppCommand(
            id: .minimizeWindow, title: "Minimize", menu: .window, key: "m",
            isSystemStandard: true
        ),
    ]

    /// Komut tablosu, indeksli kısayol düzeni uygulanmış hâlde (karar 62).
    public static func all(_ style: IndexShortcutStyle = .default) -> [AppCommand] {
        table.map { command in
            switch command.id {
            case .switchToProjectAtIndex: return command.withModifiers(style.repoModifiers)
            case .focusTerminalAtIndex: return command.withModifiers(style.terminalModifiers)
            default: return command
            }
        }
    }

    /// Menü bölümü sırasına göre gruplanmış komutlar (tablo sırası korunur).
    public static func commands(
        in section: MenuSection,
        style: IndexShortcutStyle = .default
    ) -> [AppCommand] {
        all(style).filter { $0.menu == section }
    }

    /// Settings ▸ Shortcuts tablosunun kaynağı: platform standardı olmayan,
    /// referans etiketi taşıyan komutlar, `referenceOrder` sırasında.
    public static func reference(_ style: IndexShortcutStyle = .default) -> [AppCommand] {
        all(style)
            .filter { !$0.isSystemStandard && $0.referenceTitle != nil }
            .sorted { ($0.referenceOrder ?? .max) < ($1.referenceOrder ?? .max) }
    }
}
