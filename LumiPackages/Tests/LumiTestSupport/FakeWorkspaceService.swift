import Foundation
import LumiKit

/// Deterministic workspace provider fake with injectable inspection/create
/// outcomes and call tracking for state tests.
public actor FakeWorkspaceService: WorkspaceServicing {
    public struct CreateCall: Sendable, Equatable {
        public let request: WorkspaceCreateRequest
        public init(_ request: WorkspaceCreateRequest) { self.request = request }
        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.request.project == rhs.request.project && lhs.request.name == rhs.request.name
                && lhs.request.branchName == rhs.request.branchName
                && lhs.request.copyLibrary == rhs.request.copyLibrary
        }
    }
    private var inspections: [String: Result<WorkspaceSource, Error>] = [:]
    private var defaultInspection: Result<WorkspaceSource, Error>?
    private var createOutcome: Result<WorkspaceCreateResult, Error>?
    private var copyOutcome: Result<Void, Error> = .success(())
    private var removeOutcome: Result<Void, Error> = .success(())
    private var _removeCalls: [(ProjectWorkspace, Bool)] = []
    private var inspectionDelay: Duration?
    private var createDelay: Duration?
    private var _createCalls: [CreateCall] = []
    private var _copyCalls: [(String, String)] = []

    public init() {}
    public func setInspection(_ result: Result<WorkspaceSource, Error>, for path: String) { inspections[path] = result }
    public func setDefaultInspection(_ result: Result<WorkspaceSource, Error>) { defaultInspection = result }
    public func setCreateOutcome(_ result: Result<WorkspaceCreateResult, Error>) { createOutcome = result }
    public func setCopyOutcome(_ result: Result<Void, Error>) { copyOutcome = result }
    public func setRemoveOutcome(_ result: Result<Void, Error>) { removeOutcome = result }
    public var removeCalls: [(ProjectWorkspace, Bool)] { _removeCalls }
    public func setInspectionDelay(_ delay: Duration?) { inspectionDelay = delay }
    public func setCreateDelay(_ delay: Duration?) { createDelay = delay }
    public var createCalls: [CreateCall] { _createCalls }
    public var copyCalls: [(String, String)] { _copyCalls }

    public func inspect(project: Repo) async throws -> WorkspaceSource {
        if let inspectionDelay { try? await Task.sleep(for: inspectionDelay) }
        if let result = inspections[project.path] ?? defaultInspection { return try result.get() }
        return WorkspaceSource(projectPath: project.path, scm: project.isGitRepo ? .git : .none,
            destinationDirectory: NSTemporaryDirectory())
    }
    public func create(_ request: WorkspaceCreateRequest) async throws -> WorkspaceCreateResult {
        _createCalls.append(CreateCall(request))
        if let createDelay { try await Task.sleep(for: createDelay) }
        guard let createOutcome else { throw WorkspaceFailure("fake create outcome not configured") }
        return try createOutcome.get()
    }
    public func copyLibrary(sourcePath: String, workspacePath: String) async throws {
        _copyCalls.append((sourcePath, workspacePath)); try copyOutcome.get()
    }
    public func remove(_ workspace: ProjectWorkspace, force: Bool) async throws {
        _removeCalls.append((workspace, force)); try removeOutcome.get()
    }
}
