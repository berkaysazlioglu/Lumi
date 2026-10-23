import SwiftUI
import LumiMobileKit

/// What a Projects list can ask of its screen (`ProjectsView`). Both layouts —
/// the Lumi tree and the Apple-standard one — read the model and call these;
/// navigation, sheets, confirmations and the start/spinner flow stay in the screen.
struct ProjectsListActions {
    /// Mac reachable — start buttons are disabled otherwise.
    let isOnline: Bool
    /// Path (checkout or loose folder) whose one-tap start is in flight → spinner.
    let startingPath: String?
    /// Opens an agent's chat/terminal.
    let open: (_ sessionId: String) -> Void
    /// Starts a Claude right in `path` (checkout, worktree or loose folder) and opens it.
    let start: (_ path: String) -> Void
    /// "New branch from …" sheet for a project, preset to `baseBranch`.
    let newBranch: (_ repoPath: String, _ baseBranch: String) -> Void
    /// Ends an agent on the Mac. Rows ask first with `confirmDeleteChat`.
    let delete: (_ sessionId: String) -> Void
}

/// Settings ▸ Projects Layout: the Lumi tree or an Apple-standard list.
enum ProjectsLayoutStyle: String, CaseIterable, Identifiable {
    case lumi, apple

    static let storageKey = "projectsLayoutStyle"
    static let `default` = ProjectsLayoutStyle.lumi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lumi: "Lumi"
        case .apple: "Apple"
        }
    }
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
