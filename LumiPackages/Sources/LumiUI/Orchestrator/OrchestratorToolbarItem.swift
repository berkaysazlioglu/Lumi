import LumiKit
import LumiState
import SwiftUI

/// Top bar'daki orchestrator butonu (karar 114) — docked paneli açar/kapatır,
/// popup açıksa onu kapatır (⌘J, karar 124 — `OrchestratorPresentation.toggle`).
/// Orchestrator Codex'i bir turn üzerinde çalışırken ikon accent'le yanar;
/// görülmemiş ajan olayı varsa köşede accent nokta çıkar.
public struct OrchestratorToolbarItem: View {
    @Shell private var shell

    public init() {}

    public static let iconName = "point.3.filled.connected.trianglepath.dotted"

    public var body: some View {
        IconButton(
            systemName: Self.iconName,
            label: "Orchestrator (⌘J)",
            size: .body,
            weight: .regular,
            side: TopBarMetrics.controlHeight,
            role: .toggle,
            isActive: shell.orchestratorPresentation.isPresented || shell.orchestrator.isResponding,
            action: { shell.orchestratorPresentation.toggle() }
        )
        // Karar 126: panel/popup kapalıyken ışık bu butondan çıkar ve buraya döner.
        .flightAnchor(.orchestratorButton)
        // Faz 4: popup kapalıyken görülmemiş Activity olayı accent nokta.
        .overlay(alignment: .topTrailing) {
            if shell.orchestrator.activity.unreadCount > 0 {
                Circle()
                    .fill(Theme.accentPrimary)
                    .frame(width: Theme.Spacing.sm, height: Theme.Spacing.sm)
                    .accessibilityLabel("New agent activity in the orchestrator")
            }
        }
    }
}
