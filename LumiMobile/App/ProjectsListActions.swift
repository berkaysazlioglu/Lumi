import SwiftUI
import LumiMobileKit
import LumiWire

/// What the Projects list can ask of its screen (`ProjectsView`): the list reads
/// the model and calls these; navigation, sheets, confirmations and the
/// start/spinner flow stay in the screen.
struct ProjectsListActions {
    /// Mac reachable — start buttons are disabled otherwise.
    let isOnline: Bool
    /// Path (checkout or loose folder) whose one-tap start is in flight → spinner.
    let startingPath: String?
    /// Opens an agent's chat/terminal.
    let open: (_ sessionId: String) -> Void
    /// Starts a Claude right in `path` (checkout, worktree or loose folder) and
    /// opens it; `model` picks `claude --model <alias>` (decision 133), `nil` the default.
    let start: (_ path: String, _ model: ClaudeModelAlias?) -> Void
    /// "New branch from …" sheet for a project, preset to `baseBranch`.
    let newBranch: (_ repoPath: String, _ baseBranch: String) -> Void
    /// Ends an agent on the Mac. Rows ask first with `confirmDeleteChat`.
    let delete: (_ sessionId: String) -> Void
    /// Opens a project's appearance editor (decision 132).
    let edit: (_ project: ProjectNode) -> Void
    /// Drops the project at `path` onto `target`'s place (decision 132).
    let move: (_ path: String, _ target: String) -> Void
}

/// "Delete this chat?" as a centered alert (an "are you sure?" popup). A
/// confirmation dialog rendered as a popover on iOS 26 — first away from the
/// row, then as a bubble with a lone Delete button.
private struct ConfirmDeleteChat: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content.alert("Delete this chat?", isPresented: $isPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("“\(title)” will be ended on the Mac. This can't be undone.")
        }
    }
}

extension View {
    func confirmDeleteChat(isPresented: Binding<Bool>, title: String,
                           onDelete: @escaping () -> Void) -> some View {
        modifier(ConfirmDeleteChat(isPresented: isPresented, title: title, onDelete: onDelete))
    }
}
