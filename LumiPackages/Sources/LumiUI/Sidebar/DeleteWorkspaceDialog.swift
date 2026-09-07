import LumiKit
import LumiState
import SwiftUI

/// Workspace silme onayı (karar 49, Orca `DeleteWorkspaceDialog`).
///
/// İlk deneme temiz silmedir; kirli Git worktree'si reddedilirse hata metni
/// dialogda kalır ve buton `Force Delete`e döner — zorla silme yalnız açık
/// ikinci onayla çalışır. Branch silinmez; bu dialogda söylenir.
public struct DeleteWorkspaceDialogOverlay: View {
    @Shell private var shell

    public init() {}

    public var body: some View {
        if let dialog = shell.dialogs.deleteWorkspaceDialog {
            ModalOverlay(onDismiss: shell.cancelDeleteWorkspace) {
                Panel(variant: .modal) {
                    content(dialog).padding(Theme.Spacing.xxl).frame(width: Self.width)
                }
            }
        }
    }

    private static let width: CGFloat = 440

    private func content(_ dialog: DeleteWorkspaceDialogState) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Delete Workspace")
                .font(Theme.Typography.titleMono)
                .foregroundStyle(Theme.textPrimary)
            Text(message(dialog))
                .font(Theme.Typography.bodyMono)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(dialog.workspace.path)
                .font(Theme.Typography.captionMono)
                .foregroundStyle(Theme.textMuted)
                .textSelection(.enabled)
            if let error = shell.workspaces.deleteError {
                Text(error)
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer(minLength: 0)
                Button("Cancel", action: shell.cancelDeleteWorkspace).buttonStyle(.bordered)
                Button(shell.workspaces.canForceDelete ? "Force Delete" : "Delete") {
                    Task { await shell.confirmDeleteWorkspace(force: shell.workspaces.canForceDelete) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.error)
                .disabled(shell.workspaces.isDeleting)
            }
        }
        .disabled(shell.workspaces.isDeleting)
    }

    private func message(_ dialog: DeleteWorkspaceDialogState) -> String {
        var parts: [String] = []
        switch dialog.workspace.scm {
        case .git:
            parts.append("Removes “\(dialog.workspace.name)” from Git and deletes its folder. The branch \(dialog.workspace.branch) is kept.")
        case .plastic:
            parts.append("Deletes the Plastic workspace “\(dialog.workspace.name)” and its folder. The branch \(dialog.workspace.branch) is kept on the server.")
        case .none:
            parts.append("Moves the folder “\(dialog.workspace.name)” to the Trash.")
        }
        if dialog.sessionCount > 0 {
            parts.append("\(dialog.sessionCount) running \(dialog.sessionCount == 1 ? "session" : "sessions") will be closed.")
        }
        return parts.joined(separator: " ")
    }
}

#if DEBUG
#Preview("DeleteWorkspaceDialog") {
    let shell = ShellContext.preview()
    shell.dialogs.present(.deleteWorkspace(DeleteWorkspaceDialogState(
        workspace: ProjectWorkspace(projectPath: "/p", path: "/Users/preview/lumi/workspaces/lumi/review",
                                    name: "review", branch: "feat/review", scm: .git),
        sessionCount: 2
    )))
    return DeleteWorkspaceDialogOverlay()
        .frame(width: 720, height: 420)
        .background(Theme.bgDeep)
        .environment(\.shell, shell)
}
#endif
