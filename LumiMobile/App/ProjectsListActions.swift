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
    /// Asks to delete an agent (the screen shows the confirmation).
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
