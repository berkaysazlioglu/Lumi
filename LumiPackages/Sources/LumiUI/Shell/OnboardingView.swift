import LumiKit
import LumiState
import SwiftUI

/// 3 adımlı onboarding sihirbazı: Welcome → System Checks → Ready. fail
/// bloklar, warn bloklamaz; tamamlanınca config yazılır ve Lumi All
/// Terminals'ta açılır (karar 119 — projeler kökü artık sorulmaz).
///
/// Akış/kural/check yürütme `OnboardingStore`'dadır (refactor 5.8); bu view
/// saf render + intent'tir.
struct OnboardingView: View {
    let store: OnboardingStore

    var body: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            Spacer()
            stepContent
                .frame(maxWidth: Theme.scaled(460))
            Spacer()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgDeep)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch store.step {
        case .welcome: welcomeStep
        case .checks: checksStep
        case .done: readyStep
        }
    }

    // MARK: - Adımlar

    private var welcomeStep: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Text("Lumi")
                .font(Theme.Typography.mono(.hero, weight: .semibold))
                .foregroundStyle(Theme.accentPrimary)
            Text("Manage multiple Claude Code sessions from one panel")
                .font(Theme.Typography.mono(.base))
                .foregroundStyle(Theme.textSecondary)
            Picker("", selection: providerBinding) {
                Text("Claude").tag(AgentProvider.claude)
                Text("Codex").tag(AgentProvider.codex)
            }
            .pickerStyle(.segmented)
            .frame(width: Theme.scaled(240))
            .labelsHidden()
            Text("AI provider — can be changed later in Settings")
                .font(Theme.Typography.mono(.caption))
                .foregroundStyle(Theme.textMuted)
        }
    }

    private var providerBinding: Binding<AgentProvider> {
        Binding(get: { store.provider }, set: { store.provider = $0 })
    }

    private var checksStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("System Checks")
                .font(Theme.Typography.mono(.headline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if store.isRunningChecks {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            ForEach(store.checks) { check in
                checkRow(check)
            }
            Button("Re-run Checks") {
                Task { await store.runChecks() }
            }
            .buttonStyle(.bordered)
            .disabled(store.isRunningChecks)
        }
        .task {
            await store.runChecksIfNeeded()
        }
    }

    private func checkRow(_ check: SystemCheckResult) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: statusIcon(check.status))
                .foregroundStyle(statusColor(check.status))
            VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                Text(check.label)
                    .font(Theme.Typography.mono(.body))
                    .foregroundStyle(Theme.textPrimary)
                Text(check.message)
                    .font(Theme.Typography.mono(.caption))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(2)
            }
            Spacer()
            if check.status == .fail, check.isFixable {
                Button("Fix") {
                    store.fix(check)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var readyStep: some View {
        VStack(spacing: Theme.scaled(14)) {
            Image(systemName: "checkmark.circle.fill")
                .font(Theme.Typography.ui(.splash))
                .foregroundStyle(Theme.success)
            Text("You're ready")
                .font(Theme.Typography.mono(.headline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Start a terminal, add projects, watch your agents")
                .font(Theme.Typography.mono(.body))
                .foregroundStyle(Theme.textMuted)
        }
    }

    // MARK: - Footer / akış

    private var footer: some View {
        HStack {
            if !store.isFirstStep {
                Button("Back") { store.back() }
                    .buttonStyle(.bordered)
            }
            Spacer()
            Button(store.isLastStep ? "Launch Dashboard" : "Next") {
                if store.isLastStep {
                    store.complete()
                } else {
                    store.advance()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accentVivid)
            .disabled(!store.canAdvance)
        }
        .padding(Theme.Spacing.xxl)
    }

    private func statusIcon(_ status: SystemCheckResult.Status) -> String {
        switch status {
        case .pass: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.circle.fill"
        }
    }

    private func statusColor(_ status: SystemCheckResult.Status) -> Color {
        switch status {
        case .pass: return Theme.success
        case .warn: return Theme.warning
        case .fail: return Theme.error
        }
    }
}

#if DEBUG
#Preview("OnboardingView") {
    OnboardingView(store: ShellContext.preview().onboarding)
        .frame(width: 640, height: 520)
}
#endif
