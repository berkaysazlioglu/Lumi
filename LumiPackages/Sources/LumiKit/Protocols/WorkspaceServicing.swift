import Foundation

public protocol WorkspaceServicing: Actor {
    func inspect(project: Repo) async throws -> WorkspaceSource
    func create(_ request: WorkspaceCreateRequest) async throws -> WorkspaceCreateResult
    func copyLibrary(sourcePath: String, workspacePath: String) async throws
    /// Yönetilen workspace'i SCM kaydından düşürür ve klasörünü kaldırır
    /// (karar 49). `force` kirli Git worktree'sini de siler; Plastic'te
    /// anlamı yoktur. Yalnız `~/lumi/workspaces` altındaki hedefler kabul edilir.
    func remove(_ workspace: ProjectWorkspace, force: Bool) async throws
}
