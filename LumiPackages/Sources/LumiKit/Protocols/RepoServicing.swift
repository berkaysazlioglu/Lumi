import Foundation

/// Repo keşfi + dosya sistemi izleme sınırı (design/02 §3).
public protocol RepoServicing: Actor {
    func repos() async -> [Repo]
    func setRoots(projectsRoot: String, additionalPaths: [AdditionalPath]) async

    /// Ignored bayrakları git'in kendi semantiğiyle (nested .gitignore + global +
    /// info/exclude — karar 7); git olmayan dizinde yalnız hardcoded excludes.
    func searchContents(repoPath: String, paths: [String], query: String) async throws -> ExplorerContentResult
    func editFile(repoPath: String, edit: ExplorerFileEdit) async throws
    func capabilities(repoPath: String) async -> ProjectCapabilities
    func fileTree(repoPath: String) async -> [FileTreeNode]
    /// Aktif repo recursive izlenir (FSEvents, 500ms coalescing);
    /// git panellerinin canlılığı da bu event'e bağlıdır (.git değişimleri dahil).
    func watchFileTree(repoPath: String) async
    func unwatchFileTree(repoPath: String) async

    /// `nonisolated`: tüketici Task'ı KURULMADAN ÖNCE senkron alınabilmeli
    /// (refactor 3.4/5.6). Actor hop'u arkasında alınırsa boot penceresinde
    /// gönderilen event'ler kaybolur.
    nonisolated func events() -> AsyncStream<RepoEvent>
}
