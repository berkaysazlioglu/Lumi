import LumiKit
import SwiftUI

/// Split-button dropdown'unun İÇERİĞİ (karar 54).
///
/// Çağıranlar — topbar öğesi ve boş durum placeholder'ı — listeyi burada TEK
/// yerden alır. Ana buton aktif sağlayıcıyı açtığı için o sağlayıcı listeye
/// girmez. Spawn kapsamın intent'ine gider: repo'da checkout, All Terminals'ta
/// serbest konum (karar 108).
@MainActor
enum NewTerminalMenu {
    static func items(shell: ShellContext, scope: TerminalScope) -> [NewTerminalMenuItem] {
        let active = shell.settings.current.aiProvider
        var items = AgentProvider.allCases
            .filter { $0 != active }
            .map { provider in
                NewTerminalMenuItem(label: "New \(provider.displayName)", glyph: .provider(provider)) {
                    shell.spawnTerminal(in: scope, command: provider.launchCommand)
                }
            }
        items.append(NewTerminalMenuItem(label: "New DeepSeek", glyph: .symbol("sparkles")) {
            // Kurulu değilse store toast atar ve terminal açılmaz.
            guard let command = shell.deepSeek.launchCommandOrWarn() else { return }
            shell.spawnTerminal(in: scope, command: command, task: "DeepSeek")
        })
        items.append(NewTerminalMenuItem(label: "New Bash", glyph: .symbol("terminal")) {
            shell.spawnTerminal(in: scope, command: nil, task: "Bash")
        })
        return items
    }

    /// Karar 108: All Terminals'ın konum bölümü — home, projeler kökleri, son
    /// kullanılanlar ve klasör seçici. Seçim yalnız geçerli konumu değiştirir;
    /// terminal ana butonla ya da yukarıdaki satırlarla açılır. Repo yüzeyinde
    /// boştur (spawn checkout'ta olur).
    static func locationItems(shell: ShellContext, scope: TerminalScope) -> [NewTerminalMenuItem] {
        guard scope == .all else { return [] }
        let store = shell.looseTerminals
        let current = store.currentLocation
        var items = store.candidates(for: shell.settings.current).map { location in
            NewTerminalMenuItem(
                label: location.label,
                glyph: .symbol(symbol(for: location.kind)),
                isSelected: location.path == current
            ) {
                store.select(location.path)
            }
        }
        items.append(NewTerminalMenuItem(label: "Choose Folder…", glyph: .symbol("folder.badge.plus")) {
            Task { @MainActor in
                guard let path = await shell.actions.chooseFolder() else { return }
                store.select(path)
            }
        })
        return items
    }

    /// All Terminals'ta ana butonun yanında görünen konum etiketi.
    static func locationLabel(shell: ShellContext, scope: TerminalScope) -> String? {
        scope == .all ? shell.looseTerminals.currentLocationLabel : nil
    }

    private static func symbol(for kind: LooseTerminalLocation.Kind) -> String {
        switch kind {
        case .home: "house"
        case .sourceRoot: "folder"
        case .recent: "clock.arrow.circlepath"
        }
    }
}
