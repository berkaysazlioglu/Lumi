import LumiKit
import LumiState
import SwiftUI

/// Terminals route'unun içeriği (Faz 6.3 — eski `RootView.repoContent`).
///
/// Minimize şeridi, boş-repo durumu ve maximized ⇄ grid seçimi artık route'un
/// İÇ meselesidir; kabuk yalnız "hangi route" sorusunu bilir.
public struct TerminalsRouteView: View {
    private let repoPath: String?

    @Shell private var shell

    public init(repoPath: String?) {
        self.repoPath = repoPath
    }

    public var body: some View {
        if let repoPath {
            content(repoPath)
                .padding(Theme.Spacing.lg)
        } else {
            WelcomeView()
        }
    }

    @ViewBuilder
    private func content(_ repoPath: String) -> some View {
        let visible = shell.terminals.visibleTerminals(in: repoPath)
        let minimized = shell.terminals.minimizedTerminals(in: repoPath)
        let maximizedID = shell.layout.maximizedTerminal(in: repoPath)
        VStack(spacing: Theme.Spacing.md) {
            if !minimized.isEmpty {
                // Minimize şeridi: tıklama yalnız restore eder, odak vermez.
                TerminalChipStrip(label: "Minimized:", items: minimized) {
                    shell.terminals.restore($0)
                }
            }
            if visible.isEmpty {
                emptyState(repoPath)
            } else if let maximizedID,
                      let maxMeta = visible.first(where: { $0.id == maximizedID }) {
                let isAwaitingDecision = shell.terminals.awaitingDecisionIDs.contains(maximizedID)
                MaximizedTerminalView(
                    maximized: maxMeta,
                    others: visible.filter { $0.id != maximizedID },
                    isStalled: shell.terminals.isStalled(maximizedID),
                    isAwaitingDecision: isAwaitingDecision,
                    needsAttention: TerminalAttention.isNeeded(
                        status: maxMeta.status,
                        isAwaitingDecision: isAwaitingDecision,
                        isSelected: shell.terminals.activeTerminalID == maximizedID
                    ),
                    viewProvider: shell.viewProvider,
                    promptQueue: shell.promptQueue,
                    onSwitch: { shell.layout.maximize($0, in: repoPath) },
                    onMinimize: { shell.terminals.minimize($0) },
                    onClose: { shell.terminals.close($0) },
                    onRestore: { shell.layout.restoreMaximize(in: repoPath) }
                )
            } else {
                TerminalGridView(
                    terminals: visible,
                    layout: shell.layout.gridLayout(for: repoPath),
                    activeTerminalID: shell.terminals.activeTerminalID,
                    stalledIDs: shell.terminals.stalledIDs,
                    awaitingDecisionIDs: shell.terminals.awaitingDecisionIDs,
                    viewProvider: shell.viewProvider,
                    promptQueue: shell.promptQueue,
                    onFocus: { shell.terminals.focus($0) },
                    onMinimize: { shell.terminals.minimize($0) },
                    onMaximize: { shell.layout.maximize($0, in: repoPath) },
                    onClose: { shell.terminals.close($0) },
                    isArranging: shell.layout.isArranging(in: repoPath),
                    onSwap: { shell.terminals.swap($0, $1) },
                    onEndArranging: { shell.toggleArrangingTerminals(in: repoPath) },
                    onArrangeFocusLost: { shell.layout.endArranging() }
                )
            }
        }
    }

    private func emptyState(_ repoPath: String) -> some View {
        EmptyStatePlaceholder("No terminals in this repo", density: .full) {
            // Topbar ile aynı modern split-button (DRY): hover'da dropdown açılır.
            NewTerminalButton(
                provider: shell.settings.current.aiProvider,
                onNewProvider: {
                    shell.terminals.spawn(
                        in: repoPath,
                        command: shell.settings.current.aiProvider.launchCommand
                    )
                },
                items: NewTerminalMenu.items(shell: shell, repoPath: repoPath)
            )
        }
    }
}
