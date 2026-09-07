import LumiKit
import LumiState
import SwiftUI

/// Arka planda süren / yeni biten workspace oluşturmasının sidebar satırı
/// (karar 47): spinner, sonuç ve kurtarma eylemleri ilgili projenin altında.
struct WorkspaceOperationRow: View {
    @Shell private var shell

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                if shell.workspaces.isCreating {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: shell.workspaces.lastCreated == nil ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundStyle(shell.workspaces.lastCreated == nil ? Theme.warning : Theme.success)
                }
                Text(shell.workspaces.name)
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            if shell.workspaces.isCreating {
                Text(shell.workspaces.phaseText)
                    .font(Theme.Typography.captionMono).foregroundStyle(Theme.textSecondary)
            } else {
                if let message = shell.workspaces.errorMessage ?? shell.workspaces.warningMessage {
                    Text(message).font(Theme.Typography.captionMono).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack { actions }
                    VStack(alignment: .leading) { actions }
                }
            }
        }
        .padding(.leading, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.sm)
    }

    @ViewBuilder
    private var actions: some View {
        if shell.workspaces.needsSave {
            Button("Retry Save") { Task { await shell.workspaces.retrySave() } }
        }
        if shell.workspaces.libraryNeedsRetry {
            Button("Retry Library") { Task { await shell.workspaces.retryLibrary() } }
        }
        if let created = shell.workspaces.lastCreated, !shell.workspaces.needsSave {
            Button(shell.workspaces.libraryNeedsRetry ? "Open without Library" : "Open") {
                shell.openCreatedWorkspace(created, agent: shell.workspaces.agent)
                shell.workspaces.clearForm()
            }
        } else if shell.workspaces.lastCreated == nil {
            Button("Retry") { shell.workspaces.startCreation(projects: shell.repos.repos) }
        }
        Button("Dismiss") { shell.workspaces.clearForm() }
    }
}
