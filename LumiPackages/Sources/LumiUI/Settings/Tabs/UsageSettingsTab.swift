import LumiKit
import LumiState
import SwiftUI

/// Sağlayıcı başına kullanım göstergesi anahtarları + otomatik yenileme
/// (karar 32).
struct UsageSettingsTab: SettingsTabContent {
    static let tab: SettingsTab = .usage

    @Shell private var shell

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
            LumiSectionTitle(
                title: "Usage Indicators",
                description: "Show a usage button in the top bar for each provider you use."
            )
            InfoCard(
                "A provider you turn off is not shown and is never queried — no requests "
                    + "are made for it, manual or automatic. Claude usage is read from your "
                    + "Claude subscription; Codex usage is read from your signed-in Codex CLI."
            )
            ForEach(AgentProvider.allCases, id: \.self) { provider in
                indicatorToggle(for: provider)
            }
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
            LumiSectionTitle(
                title: "Usage Auto-Refresh",
                description: "Refresh the enabled usage indicators automatically on an interval."
            )
            InfoCard(
                "When enabled, Lumi re-checks your limits every interval — but only while "
                    + "you're actively using your Mac (recent keyboard/mouse input). It never "
                    + "runs while the Mac is asleep."
            )
            LumiToggleRow(
                title: "Auto-Refresh",
                hint: "Re-check usage automatically while you're active",
                isOn: Binding(
                    get: { shell.settings.current.usageAutoRefresh.enabled },
                    set: { value in updateAutoRefresh { $0.enabled = value } }
                )
            ) {
                intervalPicker
            }
            ForEach(shell.settings.current.usageIndicators.enabledProviders, id: \.self) { provider in
                if let store = shell.usage[provider] {
                    // Topbar popover'ının alt bilgisiyle AYNI bileşen
                    // (refactor 7.9): durum sırası `UsageStore.statusKind`'da
                    // bir kez kararlaştırılır, burada yeniden türetilmez.
                    UsageStatusRow(kind: store.statusKind, provider: store.provider)
                }
            }
        }
    }

    private func indicatorToggle(for provider: AgentProvider) -> some View {
        LumiToggleRow(
            title: provider.displayName,
            hint: "Show \(provider.displayName) usage in the top bar",
            isOn: Binding(
                get: { shell.settings.current.usageIndicators.isEnabled(provider) },
                set: { value in
                    shell.settings.setUsageIndicators(
                        shell.settings.current.usageIndicators.setting(value, for: provider)
                    )
                }
            )
        )
    }

    private var intervalPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Check interval")
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textMuted)
            LumiSegmented(
                options: UsageAutoRefresh.allowedIntervals.map {
                    .init(value: $0, label: UsageAutoRefresh.intervalLabel($0))
                },
                selection: Binding(
                    get: { shell.settings.current.usageAutoRefresh.intervalMinutes },
                    set: { value in updateAutoRefresh { $0.intervalMinutes = value } }
                )
            )
        }
        .padding(.top, Theme.Spacing.xs)
    }

    private func updateAutoRefresh(
        _ mutate: @escaping @Sendable (inout UsageAutoRefresh) -> Void
    ) {
        shell.settings.updateUsageAutoRefresh(mutate)
    }
}

#if DEBUG
#Preview("Usage") {
    SettingsTabPreview(.usage)
}
#endif
