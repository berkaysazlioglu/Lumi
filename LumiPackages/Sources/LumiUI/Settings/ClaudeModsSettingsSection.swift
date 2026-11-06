import AppKit
import LumiKit
import LumiState
import SwiftUI

/// Settings ▸ Agent ▸ Claude Mods (karar 142): mod klasöründeki her mod için
/// bir anahtar. Açık modlar yeni Lumi terminallerindeki claude'a
/// `CLAUDE_CODE_PLUGIN_DIRS` ile yüklenir; kullanıcının eklediği mod açılana
/// kadar kapalıdır.
struct ClaudeModsSettingsSection: View {
    @Shell private var shell

    private var store: ClaudeModStore { shell.claudeMods }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Claude Mods", icon: "puzzlepiece.extension")
                .padding(.bottom, Theme.Spacing.md)
            if store.mods.isEmpty {
                InfoCard("No mods in \(store.directory). A Claude Code plugin folder placed there "
                    + "appears here, switched off until you turn it on.")
                    .padding(.bottom, Theme.Spacing.lg)
            }
            ForEach(store.mods) { mod in
                LumiField(title: mod.name, hint: hint(for: mod)) {
                    LumiToggleSwitch(
                        isOn: Binding(
                            get: { ClaudeMods.isEnabled(mod, in: shell.settings.current) },
                            set: { shell.settings.setClaudeModEnabled(mod.id, $0) }
                        ),
                        label: mod.name
                    )
                }
            }
            LumiField(
                title: "Mods Folder",
                hint: "Mods you add start switched off. Turning a mod on or off applies to Claude "
                    + "sessions started afterwards; edits to a mod's files reload in running sessions.",
                isLast: true
            ) {
                HStack(spacing: Theme.Spacing.md) {
                    LumiBrowseButton(icon: "folder", label: "Open Folder", action: openFolder)
                    LumiBrowseButton(icon: "arrow.clockwise", label: "Rescan") {
                        Task { await store.reload() }
                    }
                }
            }
        }
        .task { await store.reload() }
    }

    private func hint(for mod: ClaudeMod) -> String {
        let source = mod.isBundled ? "Lumi" : (mod.version.map { "v\($0)" } ?? "Your mod")
        var hint = mod.description.flatMap { $0.isEmpty ? nil : "\($0) · \(source)" } ?? source
        // Karar 143 ek: paylaşım sürerken kapatıldı; paylaşım bitince önceki hâline döner.
        if shell.settings.current.hubSuspendedClaudeMods[mod.id] != nil {
            hint += " · Off while this Mac is shared as a hub; restored when sharing stops."
        }
        return hint
    }

    private func openFolder() {
        guard let url = store.folderForOpening() else { return }
        NSWorkspace.shared.open(url)
    }
}
