import LumiKit
import SwiftUI

/// Split-button dropdown'unun İÇERİĞİ (karar 54).
///
/// Çağıranlar — topbar öğesi ve boş durum placeholder'ı — listeyi burada TEK
/// yerden alır. Ana buton aktif sağlayıcıyı açtığı için o sağlayıcı listeye
/// girmez. Spawn kapsamın intent'ine gider: repo'da checkout, All Terminals'ta
/// serbest konum (karar 108). Ayar açıksa listenin başında Claude model
/// kısayolları durur (karar 121) — aktif sağlayıcı Claude olsa da.
@MainActor
enum NewTerminalMenu {
    static func items(shell: ShellContext, scope: TerminalScope) -> [NewTerminalMenuItem] {
        let active = shell.settings.current.aiProvider
        var items = modelItems(shell: shell, scope: scope)
        items += AgentProvider.allCases
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

    /// Karar 121: `claude --model <takma ad>`; oturum kimliği spawn'da yine
    /// enjekte edilir, kart başlığı modelin adını taşır.
    private static func modelItems(shell: ShellContext, scope: TerminalScope) -> [NewTerminalMenuItem] {
        guard shell.settings.current.claudeModelShortcutsEnabled else { return [] }
        return ClaudeModelAlias.allCases.map { model in
            NewTerminalMenuItem(label: "New Claude \(model.displayName)", glyph: .provider(.claude)) {
                shell.spawnTerminal(in: scope, command: model.launchCommand, task: model.displayName)
            }
        }
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
