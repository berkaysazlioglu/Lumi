import Foundation
import LumiKit
import Observation

@Observable
@MainActor
public final class ProjectWorkspaceStore {
    public var name = ""
    public var branchName = ""
    public var agent: WorkspaceAgent = .claude
    public var copyLibrary = false
    public private(set) var selectedProjectPath: String?
    public private(set) var source: WorkspaceSource?
    public private(set) var isInspecting = false
    public private(set) var isCreating = false
    public private(set) var errorMessage: String?
    public private(set) var lastCreated: ProjectWorkspace?
    public private(set) var records: [ProjectWorkspace] = []
    public private(set) var missingWorkspacePaths = Set<String>()
    private var pendingRecords: [String: ProjectWorkspace] = [:]
    private var libraryWarning: String?
    private var saveWarning: String?
    @ObservationIgnored private let service: any WorkspaceServicing
    @ObservationIgnored private let config: any ConfigServicing
    @ObservationIgnored private let repos: RepoStore
    @ObservationIgnored private let toasts: ToastStore
    @ObservationIgnored private var inspectionGeneration = 0
    @ObservationIgnored private var catalogGeneration = 0

    public init(service: any WorkspaceServicing, config: any ConfigServicing, repos: RepoStore, toasts: ToastStore) {
        self.service = service
        self.config = config
        self.repos = repos
        self.toasts = toasts
    }

    public var needsSave: Bool { lastCreated.map { pendingRecords[$0.path] != nil } ?? false }
    public var libraryNeedsRetry: Bool { lastCreated != nil && libraryWarning != nil }
    public var warningMessage: String? {
        let messages = [saveWarning, libraryWarning].compactMap { $0 }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    public func load() async { updateRecords(await config.config().workspaces) }

    public func updateRecords(_ records: [ProjectWorkspace]) {
        var merged: [String: ProjectWorkspace] = [:]
        for record in records { merged[record.path] = record }
        for record in pendingRecords.values { merged[record.path] = record }
        self.records = merged.values.sorted { $0.path < $1.path }
        repos.setWorkspaces(self.records)
        refreshMissingPaths()
    }

    @discardableResult
    public func addProject(path: String) async -> Bool {
        let canonical = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL.resolvingSymlinksInPath().path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical, isDirectory: &isDirectory), isDirectory.boolValue else {
            toasts.show(.error, title: "Project folder is unavailable", message: canonical)
            return false
        }
        if repos.repos.contains(where: { $0.path == canonical }) { return true }
        let entry = AdditionalPath(id: UUID().uuidString, path: canonical, type: .repo)
        do {
            try await config.updateConfig { config in
                guard !config.additionalPaths.contains(where: {
                    URL(fileURLWithPath: ($0.path as NSString).expandingTildeInPath)
                        .standardizedFileURL.resolvingSymlinksInPath().path == canonical
                }) else { return }
                config.additionalPaths.append(entry)
            }
            let updated = await config.config()
            await repos.applyRoots(projectsRoot: updated.projectsRoot, additionalPaths: updated.additionalPaths)
            return true
        } catch {
            toasts.show(.error, title: "Project could not be added", message: error.localizedDescription)
            return false
        }
    }

    public func selectProject(_ repo: Repo) async {
        guard !isCreating else { return }
        clearForm()
        selectedProjectPath = repo.path
        let generation = inspectionGeneration
        isInspecting = true
        do {
            let inspected = try await service.inspect(project: repo)
            guard generation == inspectionGeneration, selectedProjectPath == repo.path else { return }
            source = inspected
        } catch {
            guard generation == inspectionGeneration else { return }
            errorMessage = error.localizedDescription
        }
        if generation == inspectionGeneration { isInspecting = false }
    }

    public var destinationPath: String {
        guard let source else { return "" }
        let component = WorkspaceName.slug(name)
        return component.isEmpty ? source.destinationDirectory
            : (source.destinationDirectory as NSString).appendingPathComponent(component)
    }

    public var canCreate: Bool {
        guard let source else { return false }
        let slug = WorkspaceName.slug(name)
        return !isInspecting && !isCreating && lastCreated == nil && source.scm != .none
            && !slug.isEmpty && slug.utf8.count <= 120
    }

    public var phaseText: String {
        if isInspecting { return "Inspecting project…" }
        if isCreating { return lastCreated == nil ? "Creating workspace…" : "Finishing workspace…" }
        return "Create workspace"
    }

    @discardableResult
    public func create(projects: [Repo]) async -> ProjectWorkspace? {
        guard !isCreating, lastCreated == nil else { return nil }
        guard canCreate, let project = projects.first(where: { $0.path == selectedProjectPath }) else {
            errorMessage = "Enter a valid name and select a Git or Plastic project."
            return nil
        }
        isCreating = true
        errorMessage = nil
        libraryWarning = nil
        saveWarning = nil
        defer { isCreating = false }
        let override = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = WorkspaceCreateRequest(project: project, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            branchName: override.isEmpty ? nil : override, copyLibrary: copyLibrary,
            knownProjectPaths: repos.repos.map(\.path))
        do {
            let result = try await service.create(request)
            lastCreated = result.workspace
            libraryWarning = result.warning
            pendingRecords[result.workspace.path] = result.workspace
            updateRecords(records)
            await save(result.workspace)
            return result.workspace
        } catch {
            errorMessage = error.localizedDescription
            toasts.show(.error, title: "Workspace creation failed", message: error.localizedDescription)
            return nil
        }
    }

    public func retryLibrary() async {
        guard !isCreating, libraryNeedsRetry, let created = lastCreated, let source else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            try await service.copyLibrary(sourcePath: source.projectPath, workspacePath: created.path)
            libraryWarning = nil
        } catch { libraryWarning = "Library could not be copied: \(error.localizedDescription)" }
    }

    @discardableResult
    public func retrySave() async -> Bool {
        guard !isCreating else { return false }
        guard needsSave, let created = lastCreated else { return true }
        isCreating = true
        defer { isCreating = false }
        await save(created)
        return !needsSave
    }

    private func save(_ record: ProjectWorkspace) async {
        do {
            try await config.updateConfig { config in
                config.workspaces.removeAll { $0.path == record.path }
                config.workspaces.append(record)
            }
            pendingRecords.removeValue(forKey: record.path)
            saveWarning = nil
            updateRecords(await config.config().workspaces)
        } catch {
            saveWarning = "Workspace created at \(record.path), but its registration could not be saved: \(error.localizedDescription)"
        }
    }

    public func clearForm() {
        guard !isCreating else { return }
        inspectionGeneration += 1
        selectedProjectPath = nil
        source = nil
        name = ""
        branchName = ""
        copyLibrary = false
        errorMessage = nil
        libraryWarning = nil
        saveWarning = nil
        lastCreated = nil
        isInspecting = false
    }

    public func isMissing(_ record: ProjectWorkspace) -> Bool { missingWorkspacePaths.contains(record.path) }

    private func refreshMissingPaths() {
        catalogGeneration += 1
        let generation = catalogGeneration
        let paths = records.map(\.path)
        Task { [weak self] in
            let missing = await Task.detached(priority: .utility) {
                Set(paths.filter { path in
                    var directory: ObjCBool = false
                    return !FileManager.default.fileExists(atPath: path, isDirectory: &directory) || !directory.boolValue
                })
            }.value
            guard let self, generation == self.catalogGeneration else { return }
            self.missingWorkspacePaths = missing
        }
    }

    public func workspaces(for projectPath: String) -> [ProjectWorkspace] { records.filter { $0.projectPath == projectPath } }
}
