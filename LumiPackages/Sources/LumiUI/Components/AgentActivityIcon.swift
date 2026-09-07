import LumiKit
import SwiftUI

/// Sidebar ajan satırının durum glifi (karar 51, Orca `AgentStateDot`):
/// çalışıyor → spinner, karar bekliyor → zil, bitti → yeşil tik, hata →
/// kırmızı çarpı, boşta → soluk nokta. Kimlik ikonu (`TerminalIdentityIcon`)
/// ayrı bir gliftir; iki anlam tek ikona kaynaştırılmaz (karar 45).
struct AgentActivityIcon: View {
    let state: AgentActivityState
    var size: Theme.Typography.Size = .label

    var body: some View {
        glyph
            .frame(width: size.points, height: size.points)
            .accessibilityLabel(state.title)
            .help(state.title)
    }

    @ViewBuilder
    private var glyph: some View {
        switch state {
        case .running:
            ProgressView().controlSize(.mini).tint(Theme.warning)
        case .awaitingDecision:
            Image(systemName: "bell.fill").font(Theme.Typography.ui(size)).foregroundStyle(Theme.warning)
        case .done:
            Image(systemName: "checkmark.circle").font(Theme.Typography.ui(size)).foregroundStyle(Theme.success)
        case .failed:
            Image(systemName: "xmark.circle").font(Theme.Typography.ui(size)).foregroundStyle(Theme.error)
        case .idle:
            Circle().fill(Theme.textMuted).padding(size.points / 4)
        }
    }
}

#if DEBUG
#Preview("AgentActivityIcon") {
    HStack(spacing: Theme.Spacing.lg) {
        AgentActivityIcon(state: .running)
        AgentActivityIcon(state: .awaitingDecision)
        AgentActivityIcon(state: .done)
        AgentActivityIcon(state: .failed)
        AgentActivityIcon(state: .idle)
    }
    .padding(Theme.Spacing.xxl)
    .background(Theme.bgSurface)
}
#endif
