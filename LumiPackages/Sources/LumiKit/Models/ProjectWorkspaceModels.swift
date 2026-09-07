import Foundation

public enum WorkspaceSCM: String, Sendable, Equatable, CaseIterable {
    case git, plastic, none

    public var title: String {
        switch self {
        case .git: "Git"
        case .plastic: "Plastic SCM"
        case .none: "Folder"
        }
    }
}

public struct ProjectWorkspace: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let projectPath: String
    public let path: String
    public let name: String
    public let branch: String
    public let scm: WorkspaceSCM

    public init(projectPath: String, path: String, name: String, branch: String, scm: WorkspaceSCM) {
        self.projectPath = projectPath
        self.path = path
        self.name = name
        self.branch = branch
        self.scm = scm
    }

    public var repo: Repo {
        Repo(name: name, path: path, isGitRepo: scm == .git, source: .standalone)
    }
}

public struct WorkspaceSource: Sendable, Equatable {
    public let projectPath: String
    public let scm: WorkspaceSCM
    public let branch: String
    public let revision: String
    public let repositorySpec: String?
    public let destinationDirectory: String
    public let isUnityProject: Bool
    public let hasLibrary: Bool
    public let libraryCopyBlockedReason: String?

    public init(
        projectPath: String, scm: WorkspaceSCM, branch: String = "", revision: String = "",
        repositorySpec: String? = nil, destinationDirectory: String,
        isUnityProject: Bool = false, hasLibrary: Bool = false,
        libraryCopyBlockedReason: String? = nil
    ) {
        self.projectPath = projectPath
        self.scm = scm
        self.branch = branch
        self.revision = revision
        self.repositorySpec = repositorySpec
        self.destinationDirectory = destinationDirectory
        self.isUnityProject = isUnityProject
        self.hasLibrary = hasLibrary
        self.libraryCopyBlockedReason = libraryCopyBlockedReason
    }

    public func suggestedBranch(name: String) -> String {
        let slug = WorkspaceName.slug(name)
        return scm == .plastic ? "\(branch.isEmpty ? "/main" : branch)/\(slug)" : slug
    }
}

public enum WorkspaceName {
    public static func slug(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let parts = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
        return parts.joined(separator: "-").trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
    }
}

public struct WorkspaceCreateRequest: Sendable {
    public let project: Repo
    public let name: String
    public let branchName: String?
    public let createNewBranch: Bool
    public let copyLibrary: Bool
    public let knownProjectPaths: [String]

    public init(project: Repo, name: String, branchName: String? = nil, createNewBranch: Bool = true, copyLibrary: Bool = false, knownProjectPaths: [String] = []) {
        self.project = project
        self.name = name
        self.branchName = branchName
        self.createNewBranch = createNewBranch
        self.copyLibrary = copyLibrary
        self.knownProjectPaths = knownProjectPaths
    }
}

public struct WorkspaceCreateResult: Sendable, Equatable {
    public let workspace: ProjectWorkspace
    public let warning: String?

    public init(workspace: ProjectWorkspace, warning: String? = nil) {
        self.workspace = workspace
        self.warning = warning
    }
}

public enum WorkspaceAgent: String, CaseIterable, Sendable {
    case claude, codex, shell, none

    public var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .shell: "Shell"
        case .none: "Don't start a session"
        }
    }

    public var command: String? {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        case .shell, .none: nil
        }
    }
}

public struct WorkspaceFailure: LocalizedError, Sendable, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
