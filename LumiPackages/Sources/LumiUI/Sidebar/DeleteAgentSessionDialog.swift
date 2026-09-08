import LumiKit
import LumiState
import SwiftUI

/// Agent History oturum silme onayı (karar 53). Log ve alt ajan kayıtları
/// çöp kutusuna taşınır; oturum artık resume edilemez.
public struct DeleteAgentSessionDialogOverlay: View {
    @Shell private var shell

    public init() {}

    public var body: some View {
        if let dialog = shell.dialogs.deleteAgentSessionDialog {
            ModalOverlay(onDismiss: shell.cancelDeleteAgentSession) {
                Panel(variant: .modal) {
                    content(dialog).padding(Theme.Spacing.xxl).frame(width: Self.width)
                }
            }
        }
    }

    private static let width: CGFloat = 440

    private func content(_ dialog: DeleteAgentSessionDialogState) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Delete Session")
                .font(Theme.Typography.titleMono)
                .foregroundStyle(Theme.textPrimary)
            Text(message(dialog.entry))
                .font(Theme.Typography.bodyMono)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(dialog.entry.title)
                .font(Theme.Typography.captionMono)
                .foregroundStyle(Theme.textMuted)
                .lineLimit(3)
                .textSelection(.enabled)
            HStack {
                Spacer(minLength: 0)
                Button("Cancel", action: shell.cancelDeleteAgentSession).buttonStyle(.bordered)
                Button("Delete") { Task { await shell.confirmDeleteAgentSession() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.error)
            }
        }
        .disabled(shell.agentHistory.isTransferring)
    }

    private func message(_ entry: AgentHistoryEntry) -> String {
        var parts = ["Moves this \(entry.provider.rawValue.capitalized) session log to the Trash. It can no longer be resumed."]
        if !entry.subagents.isEmpty {
            parts.append("\(entry.subagents.count) subagent \(entry.subagents.count == 1 ? "transcript" : "transcripts") will be removed too.")
        }
        return parts.joined(separator: " ")
    }
}

#if DEBUG
#Preview("DeleteAgentSessionDialog") {
    let shell = ShellContext.preview()
    shell.dialogs.present(.deleteAgentSession(DeleteAgentSessionDialogState(
        entry: AgentHistoryEntry(provider: .claude, sessionID: "abc", title: "Fix flaky tests", updatedAt: .now, logPath: "/tmp/abc.jsonl"),
        projectPath: "/tmp"
    )))
    return DeleteAgentSessionDialogOverlay().environment(shell).frame(width: 800, height: 500)
}
#endif
