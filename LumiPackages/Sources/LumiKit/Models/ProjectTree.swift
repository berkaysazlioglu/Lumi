import Foundation

/// Projects panelinin `Proje → Checkout → Ajan` ağacı — view'sız, tek kaynak
/// (karar 91 / 114). Telefonun `projects` anlık görüntüsü ve orchestrator'ın
/// `list_projects` aracı aynı ağaçtan beslenir ki iki yüzey ayrışmasın.
public struct ProjectTreeNode: Sendable, Equatable {
    public let name: String
    public let path: String
    public let checkouts: [ProjectCheckoutNode]

    public init(name: String, path: String, checkouts: [ProjectCheckoutNode]) {
        self.name = name
        self.path = path
        self.checkouts = checkouts
    }
}

public struct ProjectCheckoutNode: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        /// Projenin kendi kökü.
        case original
        /// Lumi'nin yönettiği workspace/worktree (karar 48–50).
        case workspace
    }

    public let kind: Kind
    public let title: String
    /// Yalnız workspace'lerde bilinir; kökün dalı ağaçta taşınmaz.
    public let branch: String?
    /// `git` / `plastic` / `none`.
    public let scm: String
    public let path: String
    /// Checkout'ta koşan terminaller, en yeni aktivite önce.
    public let terminalIDs: [TerminalID]

    public init(kind: Kind, title: String, branch: String?, scm: String, path: String, terminalIDs: [TerminalID]) {
        self.kind = kind
        self.title = title
        self.branch = branch
        self.scm = scm
        self.path = path
        self.terminalIDs = terminalIDs
    }
}

public enum ProjectTree {
    /// Kökün checkout başlığı (Projects paneliyle aynı).
    public static let originalTitle = "main"

    /// Favori projeler (sıra korunur) → kökü + workspace'leri → terminaller.
    /// Repo listesinde olmayan favori atlanır.
    public static func build(
        favoritePaths: [String],
        repos: [Repo],
        workspaces: [ProjectWorkspace],
        terminals: [TerminalMeta]
    ) -> [ProjectTreeNode] {
        let repoByPath = Dictionary(repos.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })

        func terminalIDs(at path: String) -> [TerminalID] {
            terminals
                .filter { $0.repoPath == path }
                .sorted { $0.lastActivityAt > $1.lastActivityAt }
                .map(\.id)
        }

        return favoritePaths.compactMap { favoritePath in
            guard let repo = repoByPath[favoritePath] else { return nil }
            let original = ProjectCheckoutNode(
                kind: .original, title: originalTitle, branch: nil,
                scm: (repo.isGitRepo ? WorkspaceSCM.git : WorkspaceSCM.none).rawValue,
                path: repo.path, terminalIDs: terminalIDs(at: repo.path)
            )
            let managed = workspaces
                .filter { $0.projectPath == favoritePath }
                .map { workspace in
                    ProjectCheckoutNode(
                        kind: .workspace, title: workspace.name, branch: workspace.branch,
                        scm: workspace.scm.rawValue, path: workspace.path,
                        terminalIDs: terminalIDs(at: workspace.path)
                    )
                }
            return ProjectTreeNode(name: repo.name, path: repo.path, checkouts: [original] + managed)
        }
    }
}
