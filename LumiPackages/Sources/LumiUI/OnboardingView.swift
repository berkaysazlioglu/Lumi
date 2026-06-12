import LumiKit
import LumiState
import SwiftUI

/// 4 adımlı onboarding sihirbazı (spec/22): Welcome → System Checks →
/// Projects Root → Ready. fail bloklar, warn bloklamaz; tamamlanınca config
/// yazılır ve yan etkiler koordinatörden akar (repo taraması anında başlar).
struct OnboardingView: View {
    let settings: SettingsStore
    let shell: RootView.ShellActions
    let onComplete: () -> Void

    @State private var step = 0
    @State private var provider: AgentProvider = .claude
    @State private var projectsRoot = ""
    @State private var checks: [SystemCheckResult] = []
    @State private var isRunningChecks = false

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
        switch step {
        case 0: welcomeStep
        case 1: checksStep
        case 2: projectsRootStep
        default: readyStep
        }
    }

    // MARK: - Adımlar

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Text("Lumi")
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accentPrimary)
            Text("Manage multiple Claude Code sessions from one panel")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
            Picker("", selection: $provider) {
                Text("Claude").tag(AgentProvider.claude)
                Text("Codex").tag(AgentProvider.codex)
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .labelsHidden()
            Text("AI provider — can be changed later in Settings")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        }
    }

    private var checksStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Checks")
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
            if isRunningChecks {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            ForEach(checks) { check in
                HStack(spacing: 8) {
                    Image(systemName: statusIcon(check.status))
                        .foregroundStyle(statusColor(check.status))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(check.label)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                        Text(check.message)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.textMuted)
                            .lineLimit(2)
                    }
                    Spacer()
                    if check.status == .fail, check.isFixable {
                        Button("Fix") {
                            shell.fixCheck(check.id)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            }
            Button("Re-run Checks") {
                runChecks()
            }
            .buttonStyle(.bordered)
            .disabled(isRunningChecks)
        }
        .task {
            if checks.isEmpty {
                runChecks()
            }
        }
    }

    private var projectsRootStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Projects Root")
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
            Text("The folder where your repos live — first-level subdirectories are listed")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                Text(projectsRoot.isEmpty ? "(not selected)" : projectsRoot)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Theme.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Button("Browse…") {
                    Task { @MainActor in
                        if let path = await shell.chooseFolder() {
                            projectsRoot = path
                        }
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.success)
            Text("You're ready")
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
            Text("Open a repo, start a terminal, watch your agents")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        }
    }

    // MARK: - Footer / akış

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.bordered)
            }
            Spacer()
            Button(step == 3 ? "Launch Dashboard" : "Next") {
                if step == 3 {
                    complete()
                } else {
                    step += 1
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accentVivid)
            .disabled(!canAdvance)
        }
        .padding(24)
    }

    private var canAdvance: Bool {
        switch step {
        case 1:
            // fail bloklar, warn bloklamaz (spec/22)
            return !isRunningChecks && !checks.contains { $0.status == .fail }
        case 2:
            return !projectsRoot.isEmpty
        default:
            return true
        }
    }

    private func runChecks() {
        isRunningChecks = true
        Task { @MainActor in
            checks = await shell.runChecks()
            isRunningChecks = false
        }
    }

    /// Anlık-uygulama modeli sayesinde tek config yazımı yeterli:
    /// koordinatör repo taramasını ve diğer yan etkileri kendisi tetikler.
    private func complete() {
        let selectedProvider = provider
        let selectedRoot = projectsRoot
        settings.apply {
            $0.aiProvider = selectedProvider
            $0.projectsRoot = selectedRoot
        }
        onComplete()
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
