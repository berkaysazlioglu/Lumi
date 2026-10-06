import Foundation

/// Projects panelinin `Proje → Checkout → Ajan` ağacı — view'sız, tek kaynak
/// (karar 91 / 114). Telefonun `projects` anlık görüntüsü, orchestrator'ın
/// `list_projects` aracı ve panelin `Other` grubu (karar 108) aynı ağaçtan
/// beslenir ki yüzeyler ayrışmasın.
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

/// Ağaç + ağaçtaki hiçbir checkout'a ait olmayan terminallerin `Other`
/// grupları (karar 108) — telefonun ve orchestrator'ın tek okuması.
public struct ProjectTreeSnapshot: Sendable, Equatable {
    public let projects: [ProjectTreeNode]
    public let others: [LooseTerminalGroup]

    public init(projects: [ProjectTreeNode], others: [LooseTerminalGroup]) {
        self.projects = projects
        self.others = others
    }
}

public enum ProjectTree {
    /// Kökün checkout başlığı (Projects paneliyle aynı).
    public static let originalTitle = "main"
    /// Serbest terminal grubunun başlığı (karar 108).
    public static let otherTitle = "Other"

    /// Favori projeler (sıra korunur) → kökü + workspace'leri → terminaller.
    /// Repo listesinde olmayan favori ve kendisi yönetilen bir workspace olan
    /// favori atlanır — o, kendi projesinin altında durur (Projects paneli
    /// `ProjectWorkspaceStore.addedProjects` paritesi).
    public static func build(
        favoritePaths: [String],
        repos: [Repo],
        workspaces: [ProjectWorkspace],
        terminals: [TerminalMeta]
    ) -> [ProjectTreeNode] {
        let repoByPath = Dictionary(repos.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let managedPaths = Set(workspaces.map(\.path))

        func terminalIDs(at path: String) -> [TerminalID] {
            byRecentActivity(terminals.filter { $0.repoPath == path })
        }

        return favoritePaths.compactMap { favoritePath in
            guard !managedPaths.contains(favoritePath), let repo = repoByPath[favoritePath] else { return nil }
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

    /// Ağaç + `Other` grupları. Sahiplik ağacın checkout yollarıdır; Mac
    /// panelinde açık repo tab'ı da sahiplik sayılır (`NavigationStore`), uzak
    /// yüzeylerin tab'ı yoktur.
    public static func snapshot(
        favoritePaths: [String],
        repos: [Repo],
        workspaces: [ProjectWorkspace],
        terminals: [TerminalMeta],
        home: String = NSHomeDirectory()
    ) -> ProjectTreeSnapshot {
        let projects = build(favoritePaths: favoritePaths, repos: repos, workspaces: workspaces, terminals: terminals)
        let owned = projects.flatMap { $0.checkouts.map(\.path) }
        return ProjectTreeSnapshot(
            projects: projects,
            others: looseGroups(terminals: terminals, ownedPaths: owned, home: home)
        )
    }

    /// Projects ▸ `Other` (karar 108): `ownedPaths`'e girmeyen terminaller
    /// dizinlerine göre, etiket sırasıyla. Grup içi sıra girdinin sırasıdır —
    /// Mac paneli kendi ajan sıralamasını uygular, uzak yüzeyler
    /// `byRecentActivity` kullanır.
    public static func looseGroups(
        terminals: [TerminalMeta],
        ownedPaths: [String],
        home: String = NSHomeDirectory()
    ) -> [LooseTerminalGroup] {
        let loose = terminals.filter {
            LooseTerminalRule.isLoose(path: $0.repoPath, projectPaths: ownedPaths, workspacePaths: [], openTabs: [], home: home)
        }
        let paths = loose.reduce(into: [String]()) { paths, meta in
            if !paths.contains(meta.repoPath) { paths.append(meta.repoPath) }
        }
        return paths
            .map { path in
                LooseTerminalGroup(
                    path: path,
                    label: LooseTerminalPath.displayLabel(path, home: home),
                    terminals: loose.filter { $0.repoPath == path }
                )
            }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    /// Uzak yüzeylerin ajan sırası: en yeni aktivite önce.
    public static func byRecentActivity(_ terminals: [TerminalMeta]) -> [TerminalID] {
        terminals.sorted { $0.lastActivityAt > $1.lastActivityAt }.map(\.id)
    }
}
