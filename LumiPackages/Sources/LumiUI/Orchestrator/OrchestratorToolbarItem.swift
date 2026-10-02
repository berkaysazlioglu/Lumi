import LumiKit
import LumiState
import SwiftUI

/// Top bar'daki orchestrator butonu (karar 103) — popup'ı açar/kapatır (⌘J).
/// Orchestrator bir cevap üzerinde çalışırken ikon accent'le yanar; bekleyen
/// onay varsa köşede sarı, görülmemiş ajan olayı varsa mor nokta çıkar.
public struct OrchestratorToolbarItem: View {
    @Shell private var shell

    public init() {}

    static let iconName = "point.3.filled.connected.trianglepath.dotted"

    public var body: some View {
        IconButton(
            systemName: Self.iconName,
            label: "Orchestrator (⌘J)",
            size: .body,
            weight: .regular,
            side: TopBarMetrics.controlHeight,
            role: .toggle,
            isActive: shell.dialogs.isOrchestratorOpen || shell.orchestrator.isResponding,
            action: { shell.dialogs.isOrchestratorOpen.toggle() }
        )
        // Faz 3: popup kapalıyken bekleyen onay görünür kalsın.
        // Faz 4: görülmemiş Activity olayı accent nokta (onay önceliklidir).
        .overlay(alignment: .topTrailing) {
            if let dot {
                Circle()
                    .fill(dot.color)
                    .frame(width: Theme.Spacing.sm, height: Theme.Spacing.sm)
                    .accessibilityLabel(dot.label)
            }
        }
    }

    private var dot: (color: Color, label: String)? {
        if !shell.orchestrator.approvals.pending.isEmpty {
            return (Theme.warning, "Orchestrator is waiting for your approval")
        }
        if shell.orchestrator.activity.unreadCount > 0 {
            return (Theme.accentPrimary, "New agent activity in the orchestrator")
        }
        return nil
    }
}
