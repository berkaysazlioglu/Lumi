import LumiKit
import LumiState
import SwiftUI

/// 4 adımlı onboarding sihirbazı: Welcome → System Checks →
/// Projects Root → Ready. fail bloklar, warn bloklamaz; tamamlanınca config
/// yazılır ve yan etkiler koordinatörden akar (repo taraması anında başlar).
///
/// Akış/kural/check yürütme `OnboardingStore`'dadır (refactor 5.8); bu view
/// saf render + intent'tir.
struct OnboardingView: View {
    let store: OnboardingStore

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            stepContent
                .frame(maxWidth: 460)
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
        case .projectsRoot: projectsRootStep
        case .done: readyStep
        }
    }

    // MARK: - Adımlar

    private var welcomeStep: some View {
        VStack(spacing: 16) {
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
            .frame(width: 240)
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
        VStack(alignment: .leading, spacing: 12) {
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
        HStack(spacing: 8) {
            Image(systemName: statusIcon(check.status))
                .foregroundStyle(statusColor(check.status))
            VStack(alignment: .leading, spacing: 1) {
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
        .padding(.vertical, 4)
    }

    private var projectsRootStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Projects Root")
                .font(Theme.Typography.mono(.headline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("The folder where your repos live — first-level subdirectories are listed")
                .font(Theme.Typography.mono(.label))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                Text(store.projectsRoot.isEmpty ? "(not selected)" : store.projectsRoot)
                    .font(Theme.Typography.mono(.body))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Theme.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                Button("Browse…") {
                    Task { await store.chooseProjectsRoot() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(Theme.Typography.ui(.splash))
                .foregroundStyle(Theme.success)
            Text("You're ready")
                .font(Theme.Typography.mono(.headline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Open a repo, start a terminal, watch your agents")
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
        .padding(24)
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
