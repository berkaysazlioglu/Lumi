import LumiKit
import LumiState
import SwiftUI

/// Karar 115 (Orca "Hiding N discovered worktrees" paritesi): Lumi'nin
/// yönetilen kökü dışındaki worktree'ler kendiliğinden listelenmez; projenin
/// altında sayıları görünür ve `Show` hepsini kalıcı olarak listeye alır.
/// Tek tek geri gizlemek satırın `Remove from List` eylemidir.
struct HiddenWorktreesRow: View {
    let projectPath: String
    @Shell private var shell

    var body: some View {
        let hidden = shell.workspaces.hiddenWorktrees(for: projectPath)
        if !hidden.isEmpty {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "eye.slash")
                    .foregroundStyle(Theme.textMuted)
                    .accessibilityHidden(true)
                Text(hidden.count == 1 ? "1 other worktree" : "\(hidden.count) other worktrees")
                    .font(Theme.Typography.captionMono)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button("Show") { Task { await shell.workspaces.showHiddenWorktrees(for: projectPath) } }
                    .buttonStyle(.plain)
                    .font(Theme.Typography.captionMono)
                    .foregroundStyle(Theme.accentPrimary)
                    .accessibilityLabel("Show \(hidden.count) other worktrees")
            }
            .padding(.leading, Theme.Spacing.xl)
            .padding(.trailing, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .help(hidden.map(\.path).joined(separator: "\n"))
        }
    }
}
