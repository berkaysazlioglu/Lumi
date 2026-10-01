import LumiKit
import LumiState
import SwiftUI

/// FileViewer başlığındaki "Mention in Chat" (karar 100): seçili satırların
/// `@path#L…` referansını checkout'taki ajan terminaline yapıştırır.
///
/// Tek tık varsayılan hedefe (aktif / son aktif ajan terminali) gider; birden
/// çok ajan varsa yanındaki chevron hedef seçtirir. Ajan yoksa buton pasiftir
/// ve nedenini ipucunda söyler.
struct MentionInChatButton: View {
    let store: FileViewerStore

    @Shell private var shell
    @State private var showsTargets = false

    private var targets: [TerminalMeta] { shell.terminals.mentionTargets(in: store.repoPath) }

    var body: some View {
        let targets = targets
        HStack(spacing: 0) {
            pill(targets.first)
            if targets.count > 1 {
                IconButton(systemName: "chevron.down", label: "Choose agent to mention in", size: .caption) {
                    showsTargets.toggle()
                }
                .popover(isPresented: $showsTargets, arrowEdge: .bottom) {
                    PopoverMenu(items: menuItems(targets), dismiss: { showsTargets = false })
                }
            }
        }
    }

    private func pill(_ target: TerminalMeta?) -> some View {
        Button {
            if let target { shell.mentionSelection(in: target) }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "at")
                    .accessibilityHidden(true)
                Text("Mention in Chat")
            }
            .font(Theme.Typography.mono(.caption, weight: .semibold))
            .foregroundStyle(Theme.accentPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            // 3pt: markdown rozetiyle aynı ölçek dışı ara değer.
            .padding(.vertical, Theme.scaled(3))
            .background(Theme.accentPrimary.opacity(0.18))
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        .opacity(target == nil ? 0.4 : 1)
        .help(help(for: target))
    }

    private func help(for target: TerminalMeta?) -> String {
        guard let target else { return "No agent is running in this checkout" }
        return "Paste \(store.mentionReference ?? "") into \(target.displayTitle)"
    }

    private func menuItems(_ targets: [TerminalMeta]) -> [PopoverMenu.Item] {
        [.section("Mention in")] + targets.map { target in
            .action(target.displayTitle, icon: "terminal") { shell.mentionSelection(in: target) }
        }
    }
}
