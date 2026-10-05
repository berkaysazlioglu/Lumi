import LumiKit
import LumiState
import SwiftUI

/// Terminal yüzeyi route'larının içeriği (Faz 6.3 — eski `RootView.repoContent`).
///
/// Minimize şeridi, boş durum ve maximized ⇄ grid seçimi route'un İÇ
/// meselesidir; kabuk yalnız "hangi route" sorusunu bilir.
///
/// Karar 103: aynı görünüm hem repo route'unu hem All Terminals'ı çizer —
/// fark yalnız `TerminalScope`'tadır. Grid, maximize, minimize, kapatma ve
/// Edit modu kapsamın intent'lerine gider; All Terminals'ta kartlar checkout
/// etiketini taşır. Boş durumdaki spawn düğmesi All Terminals'ta serbest
/// terminali seçili konumda (varsayılan `~`) açar (karar 108).
public struct TerminalsRouteView: View {
    private let scope: TerminalScope?

    @Shell private var shell

    /// Repo route'u (`ContentRouteID.terminals`) — `nil` = açık tab yok.
    public init(repoPath: String?) {
        self.scope = repoPath.map(TerminalScope.repo)
    }

    public init(scope: TerminalScope) {
        self.scope = scope
    }

    public var body: some View {
        if let scope {
            content(scope)
                .padding(Theme.Spacing.lg)
                .environment(\.terminalCheckoutLabels, checkoutLabels(for: scope))
        } else {
            WelcomeView()
        }
    }

    @ViewBuilder
    private func content(_ scope: TerminalScope) -> some View {
        let visible = shell.terminals.visibleTerminals(in: scope)
        let minimized = shell.terminals.minimizedTerminals(in: scope)
        let maximizedID = shell.layout.maximizedTerminal(in: scope)
        VStack(spacing: Theme.Spacing.md) {
            if !minimized.isEmpty {
                // Minimize şeridi: tıklama yalnız restore eder, odak vermez.
                TerminalChipStrip(label: "Minimized:", items: minimized) {
                    shell.terminals.restore($0)
                }
            }
            if visible.isEmpty {
                emptyState(scope)
            } else if let maximizedID,
                      let maxMeta = visible.first(where: { $0.id == maximizedID }) {
                maximizedView(maxMeta, others: visible.filter { $0.id != maximizedID }, scope: scope)
            } else {
                gridView(visible, scope: scope)
            }
        }
    }

    private func maximizedView(_ maxMeta: TerminalMeta, others: [TerminalMeta], scope: TerminalScope) -> some View {
        let isAwaitingDecision = shell.terminals.awaitingDecisionIDs.contains(maxMeta.id)
        return MaximizedTerminalView(
            maximized: maxMeta,
            others: others,
            isStalled: shell.terminals.isStalled(maxMeta.id),
            isAwaitingDecision: isAwaitingDecision,
            needsAttention: TerminalAttention.isNeeded(
                status: maxMeta.status,
                isAwaitingDecision: isAwaitingDecision,
                isSelected: shell.terminals.activeTerminalID == maxMeta.id
            ),
            viewProvider: shell.viewProvider,
            promptQueue: shell.promptQueue,
            onSwitch: { shell.layout.maximize($0, in: scope) },
            onMinimize: { shell.terminals.minimize($0) },
            onClose: { shell.terminals.close($0) },
            onRestore: { shell.layout.restoreMaximize(in: scope) }
        )
    }

    private func gridView(_ visible: [TerminalMeta], scope: TerminalScope) -> some View {
        TerminalGridView(
            terminals: visible,
            layout: shell.layout.gridLayout(for: scope),
            activeTerminalID: shell.terminals.activeTerminalID,
            stalledIDs: shell.terminals.stalledIDs,
            awaitingDecisionIDs: shell.terminals.awaitingDecisionIDs,
            viewProvider: shell.viewProvider,
            promptQueue: shell.promptQueue,
            onFocus: { shell.terminals.focus($0) },
            onMinimize: { shell.terminals.minimize($0) },
            onMaximize: { shell.layout.maximize($0, in: scope) },
            onClose: { shell.terminals.close($0) },
            isArranging: shell.layout.isArranging(in: scope),
            onSwap: { shell.terminals.swap($0, $1, in: scope) },
            onEndArranging: { shell.toggleArrangingTerminals(in: scope) },
            onArrangeFocusLost: { shell.layout.endArranging() }
        )
    }

    @ViewBuilder
    private func emptyState(_ scope: TerminalScope) -> some View {
        // Topbar ile aynı split-button (DRY): chevron dropdown'u açar.
        EmptyStatePlaceholder(
            scope == .all ? "No terminals yet" : "No terminals in this repo",
            density: .full
        ) {
            ScopedNewTerminalButton(scope: scope)
        }
    }

    /// Yalnız All Terminals etiket taşır — repo görünümünde her kart aynı
    /// checkout'tadır.
    private func checkoutLabels(for scope: TerminalScope) -> [String: String] {
        guard scope == .all else { return [:] }
        let paths = Set(shell.terminals.terminals.map(\.repoPath))
        return Dictionary(uniqueKeysWithValues: paths.map { ($0, shell.checkoutLabel(for: $0)) })
    }
}
