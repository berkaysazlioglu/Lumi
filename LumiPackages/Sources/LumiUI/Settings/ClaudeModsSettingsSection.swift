import AppKit
import LumiKit
import LumiState
import SwiftUI

/// Settings ▸ Agent ▸ Claude Mods (karar 142): mod klasöründeki her mod için
/// bir anahtar. Açık modlar yeni Lumi terminallerindeki claude'a
/// `CLAUDE_CODE_PLUGIN_DIRS` ile yüklenir; çalışan claude'lar etkilenmez.
struct ClaudeModsSettingsSection: View {
    @Shell private var shell

    private var store: ClaudeModStore { shell.claudeMods }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Claude Mods", icon: "puzzlepiece.extension")
                .padding(.bottom, Theme.Spacing.md)
            if store.mods.isEmpty {
                InfoCard("No mods in \(store.directory). A Claude Code plugin folder placed there "
                    + "appears here.")
                    .padding(.bottom, Theme.Spacing.lg)
            }
            ForEach(store.mods) { mod in
                LumiField(title: mod.name, hint: hint(for: mod)) {
                    LumiToggleSwitch(
                        isOn: Binding(
                            get: { ClaudeMods.isEnabled(mod.id, in: shell.settings.current) },
                            set: { shell.settings.setClaudeModEnabled(mod.id, $0) }
                        ),
                        label: mod.name
                    )
                }
            }
            LumiField(
                title: "Mods Folder",
                hint: "Applies to Claude sessions started after a change — running sessions keep "
                    + "their mods until restarted.",
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
        let source = mod.isBundled ? "Lumi" : (mod.version.map { "v\($0)" } ?? mod.id)
        guard let description = mod.description, !description.isEmpty else { return source }
        return "\(description) · \(source)"
    }

    private func openFolder() {
        guard !store.directory.isEmpty else { return }
        let url = URL(fileURLWithPath: store.directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}
