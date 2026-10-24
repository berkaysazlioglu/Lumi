import AppKit
import LumiKit
import LumiState
import SwiftUI

/// Bağlama sheet'i (Tasks planı): adapter seçimi → (custom'da kurulum + adres
/// + token) → Verify kontrol listesi → Connect.
public struct TaskConnectOverlay: View {
    @Bindable var store: TasksStore
    @Shell private var shell

    public init(store: TasksStore) {
        self.store = store
    }

    private static var panelWidth: CGFloat { Theme.scaled(640) }
    private static var panelHeight: CGFloat { Theme.scaled(640) }

    private var flow: TaskConnectFlow? { store.connectFlow }

    public var body: some View {
        ModalOverlay(onDismiss: store.cancelConnect) {
            Panel(variant: .modal) {
                VStack(spacing: 0) {
                    header
                    divider
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 0) {
                            if flow?.reconnecting == nil {
                                LumiField(title: "Source type", hint: nil) { kindPicker }
                            }
                            if let flow, flow.kind.needsEndpoint {
                                LumiField(
                                    title: "1 · Set up your server",
                                    hint: "Paste the setup prompt into an agent working in your server's project. It builds the Lumi Tasks API and prints an address and a token."
                                ) { setupPrompt }
                                LumiField(title: "2 · Server address", hint: "https:// — or http://localhost while you develop") {
                                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                        LumiTextInput(text: binding(\.address), placeholder: "https://my-app.herokuapp.com")
                                        if let problem = flow.addressProblem {
                                            Text(problem)
                                                .font(Theme.Typography.labelMono)
                                                .foregroundStyle(Theme.error)
                                        }
                                    }
                                }
                                LumiField(title: "3 · Token", hint: "Stored in your Keychain, sent only to this server") {
                                    LumiTextInput(text: binding(\.token), placeholder: "Paste the token", isSecure: true)
                                }
                            }
                            LumiField(title: "Name", hint: "Optional — shown in the source menu", isLast: flow?.report == nil) {
                                LumiTextInput(text: binding(\.name, resetsReport: false), placeholder: "e.g. Team backlog")
                            }
                            if let report = flow?.report {
                                LumiField(title: "Verify", hint: nil, isLast: true) { TaskVerificationList(report: report) }
                            }
                        }
                        .padding(Theme.Spacing.xxl)
                    }
                    divider
                    footer
                }
            }
            .frame(width: Self.panelWidth, height: Self.panelHeight)
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
    }

    /// Akış alanına bağlama — adres/token değişince eski Verify sonucu düşer.
    private func binding(_ path: WritableKeyPath<TaskConnectFlow, String>, resetsReport: Bool = true) -> Binding<String> {
        Binding(
            get: { store.connectFlow?[keyPath: path] ?? "" },
            set: { value in
                guard store.connectFlow?[keyPath: path] != value else { return }
                store.connectFlow?[keyPath: path] = value
                if resetsReport { store.connectInputsChanged() }
            }
        )
    }

    // MARK: - Parçalar

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(flow?.reconnecting == nil ? "Connect Task Source" : "Reconnect \(flow?.name ?? "")")
                    .font(Theme.Typography.mono(.headline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(flow?.reconnecting == nil ? "Lumi reads and moves tasks on a server you own" : "Paste a new token — tasks and filters stay as they are")
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            IconButton(
                systemName: "xmark", label: "Close",
                side: Theme.scaled(28), cornerRadius: Theme.Radius.md, action: store.cancelConnect
            )
        }
        .padding(Theme.Spacing.xl)
    }

    private var kindPicker: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ForEach(TaskProviderKind.allCases, id: \.self) { kind in
                kindRow(kind)
            }
        }
    }

    private func kindRow(_ kind: TaskProviderKind) -> some View {
        let isSelected = flow?.kind == kind
        return Button { store.selectConnectKind(kind) } label: {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(Theme.Typography.ui(.body))
                    .foregroundStyle(isSelected ? Theme.accentPrimary : Theme.textMuted)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(kind.title)
                        .font(Theme.Typography.mono(.body, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(kind.subtitle)
                        .font(Theme.Typography.labelMono)
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.lg)
            .background(isSelected ? Theme.bgElevated : Theme.bgDeep)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(isSelected ? Theme.accentVivid : Theme.border, lineWidth: Theme.Stroke.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!kind.isAvailable)
        .opacity(kind.isAvailable ? 1 : 0.45)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Protokolün kanonik metni (`TaskSetupPrompt`) — kullanıcının ajanına.
    private var setupPrompt: some View {
        HStack(spacing: Theme.Spacing.md) {
            LumiActionButton(title: "Copy Setup Prompt", kind: .primary) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(TaskSetupPrompt.text, forType: .string)
                shell.toasts.show(.success, title: "Copied setup prompt", message: "Paste it into an agent working in your server's project.")
            }
            Text("Lumi Tasks Protocol v1")
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textMuted)
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            if let report = flow?.report, report.isFinished, report.hasFailure {
                LumiActionButton(title: "Copy Report for Agent") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.agentReport, forType: .string)
                    shell.toasts.show(.success, title: "Copied verification report")
                }
            }
            Spacer()
            LumiActionButton(title: "Cancel", action: store.cancelConnect)
            LumiActionButton(title: flow?.report == nil ? "Verify" : "Verify Again") {
                Task { await store.verifyConnect() }
            }
            .disabled(flow?.canVerify != true)
            LumiActionButton(title: "Connect", kind: .primary) {
                Task { await store.finishConnect() }
            }
            .disabled(flow?.canConnect != true)
        }
        .padding(Theme.Spacing.xl)
    }
}

/// Verify adımlarının canlı listesi.
struct TaskVerificationList: View {
    let report: TaskVerificationReport

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(report.steps) { step in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                    icon(step.outcome)
                        .frame(width: Theme.Row.iconColumn)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(step.title)
                            .font(Theme.Typography.bodyMono)
                            .foregroundStyle(isQuiet(step.outcome) ? Theme.textMuted : Theme.textPrimary)
                        if let detail = detail(step.outcome) {
                            Text(detail.text)
                                .font(Theme.Typography.labelMono)
                                .foregroundStyle(detail.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func icon(_ outcome: TaskVerificationStep.Outcome) -> some View {
        switch outcome {
        case .pending:
            Image(systemName: "circle").foregroundStyle(Theme.textMuted)
        case .running:
            ProgressView().controlSize(.mini)
        case .passed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
        case .skipped:
            Image(systemName: "minus.circle").foregroundStyle(Theme.textMuted)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.error)
        }
    }

    private func isQuiet(_ outcome: TaskVerificationStep.Outcome) -> Bool {
        switch outcome {
        case .pending, .skipped: true
        default: false
        }
    }

    private func detail(_ outcome: TaskVerificationStep.Outcome) -> (text: String, color: Color)? {
        switch outcome {
        case .passed(let text): text.map { ($0, Theme.textMuted) }
        case .warning(let text): (text, Theme.warning)
        case .skipped(let text): (text, Theme.textMuted)
        case .failed(let text): (text, Theme.error)
        case .pending, .running: nil
        }
    }
}
