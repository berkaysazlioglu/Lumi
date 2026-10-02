import SwiftUI
import LumiMobileKit

/// Agent status glyph (Mac `AgentActivityIcon` parity, decisions 81/97).
struct AgentActivityGlyph: View {
    let activity: AgentActivity

    var body: some View {
        glyph
            .frame(width: 16, height: 16)
            .accessibilityLabel(activity.title)
    }

    @ViewBuilder private var glyph: some View {
        switch activity {
        case .running:
            ProgressView().controlSize(.mini).tint(.orange)
        case .awaitingDecision:
            Image(systemName: "bell.fill").font(.caption).foregroundStyle(.orange)
        case .done:
            Image(systemName: "checkmark.circle").font(.caption).foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle").font(.caption).foregroundStyle(.red)
        case .idle:
            Circle().fill(Color.secondary.opacity(0.5)).frame(width: 7, height: 7)
        }
    }
}
