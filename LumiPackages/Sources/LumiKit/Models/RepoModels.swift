import Foundation

/// Diskte keşfedilen bir proje klasörü.
/// Git reposu olmayan dizinler de listelenir (`isGitRepo: false`) —
/// terminal açılabilir, git panelleri boş kalır.
public struct Repo: Sendable, Equatable, Identifiable, Hashable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let isGitRepo: Bool
    public let source: RepoSource

    public init(name: String, path: String, isGitRepo: Bool, source: RepoSource) {
        self.name = name
        self.path = path
        self.isGitRepo = isGitRepo
        self.source = source
    }
}

/// Repo'nun hangi kaynaktan keşfedildiği — sidebar/seçici gruplaması bu alanla
/// yapılır: projectsRoot grubu, her root-tipi additional path
/// kendi grubu, repo-tipi olanlar tek "Standalone Repos" grubu.
public enum RepoSource: Sendable, Equatable, Hashable {
    case projectsRoot
    case additionalRoot(path: String, label: String?)
    case standalone
}

public enum RepoEvent: Sendable, Equatable {
    case reposChanged
    case fileTreeChanged(repoPath: String)
}

public struct ProjectCapabilities: Sendable, Equatable {
    public let isGitRepo: Bool
    public let isUnityProject: Bool

    public init(isGitRepo: Bool = false, isUnityProject: Bool = false) {
        self.isGitRepo = isGitRepo
        self.isUnityProject = isUnityProject
    }
}
