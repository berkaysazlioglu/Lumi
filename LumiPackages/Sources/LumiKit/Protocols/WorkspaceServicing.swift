import Foundation

public protocol WorkspaceServicing: Actor {
    func inspect(project: Repo) async throws -> WorkspaceSource
    func create(_ request: WorkspaceCreateRequest) async throws -> WorkspaceCreateResult
    func copyLibrary(sourcePath: String, workspacePath: String) async throws
}
