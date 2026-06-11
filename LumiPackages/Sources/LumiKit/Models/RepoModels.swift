import Foundation

/// Diskte keşfedilen bir proje klasörü (spec/12, spec/21).
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
/// yapılır (spec/21 §15): projectsRoot grubu, her root-tipi additional path
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

/// Repo keşfi + dosya sistemi izleme sınırı (design/02 §3).
/// File-tree API'leri Faz 4'te eklenir (git check-ignore ile birlikte).
public protocol RepoServicing: Actor {
    func repos() async -> [Repo]
    func setRoots(projectsRoot: String, additionalPaths: [AdditionalPath]) async
    func events() -> AsyncStream<RepoEvent>
}
