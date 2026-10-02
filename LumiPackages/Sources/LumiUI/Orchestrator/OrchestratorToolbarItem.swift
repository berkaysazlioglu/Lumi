import LumiKit
import LumiState
import SwiftUI

/// Top bar'daki orchestrator butonu (karar 103) — popup'ı açar/kapatır (⌘J).
/// Orchestrator bir cevap üzerinde çalışırken ikon accent'le yanar.
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
    }
}
