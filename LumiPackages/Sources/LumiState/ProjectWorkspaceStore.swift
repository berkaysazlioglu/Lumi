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
    public var createNewBranch = true
    public private(set) var hasBackgroundOperation = false
    public private(set) var selectedProjectPath: String?
    public private(set) var source: WorkspaceSource?
    public private(set) var isInspecting = false
    public private(set) var isCreating = false
    public private(set) var errorMessage: String?
    public private(set) var lastCreated: ProjectWorkspace?
    public private(set) var records: [ProjectWorkspace] = []
    public private(set) var sidebarProjectPaths: [String] = []
    public private(set) var missingWorkspacePaths = Set<String>()
    /// Silme akışı (karar 51): sürmekte olan silmenin yolu ve son hatası.
    public private(set) var deletingPath: String?
    public private(set) var deleteError: String?
    /// Kirli Git worktree'si ilk denemede reddedilir; kullanıcı açıkça
    /// "Force Delete" derse ikinci deneme `force` ile gider (Orca paritesi).
    public private(set) var canForceDelete = false
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

    public var addedProjects: [Repo] {
        let managed = Set(records.map(\.path))
        return sidebarProjectPaths.compactMap { path in
            managed.contains(path) ? nil : repos.repo(at: path)
        }
    }

    public func updateSidebarProjects(_ paths: [String]) {
        var seen = Set<String>()
        sidebarProjectPaths = paths.filter { seen.insert($0).inserted }
    }

    public var needsSave: Bool { lastCreated.map { pendingRecords[$0.path] != nil } ?? false }
    public var libraryNeedsRetry: Bool { lastCreated != nil && libraryWarning != nil }
    public var warningMessage: String? {
        let messages = [saveWarning, libraryWarning].compactMap { $0 }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    public func load() async {
        let saved = await config.config()
        updateRecords(saved.workspaces)
        updateSidebarProjects(saved.sidebarProjectPaths)
    }

    public func updateRecords(_ records: [ProjectWorkspace]) {
        var merged: [String: ProjectWorkspace] = [:]
        for record in records { merged[record.path] = record }
        for record in pendingRecords.values { merged[record.path] = record }
        self.records = merged.values.sorted { $0.path < $1.path }
        repos.setWorkspaces(self.records)
        refreshMissingPaths()
    }

    @discardableResult
    public func addProject(_ project: Repo) async -> Bool {
        guard repos.repo(at: project.path) != nil,
              !records.contains(where: { $0.path == project.path }) else { return false }
        do {
            try await config.updateConfig { config in
                if !config.sidebarProjectPaths.contains(project.path) {
                    config.sidebarProjectPaths.append(project.path)
                }
            }
            updateSidebarProjects(await config.config().sidebarProjectPaths)
            return true
        } catch {
            toasts.show(.error, title: "Project could not be added", message: error.localizedDescription)
            return false
        }
    }

    public func removeProject(_ project: Repo) async {
        guard !(isCreating && selectedProjectPath == project.path) else { return }
        do {
            try await config.updateConfig { $0.sidebarProjectPaths.removeAll { $0 == project.path } }
            updateSidebarProjects(await config.config().sidebarProjectPaths)
        } catch {
            toasts.show(.error, title: "Project could not be removed", message: error.localizedDescription)
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
            createNewBranch = inspected.scm != .plastic
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

    /// The store owns this task so closing the modal cannot cancel creation.
    @discardableResult
    public func startCreation(projects: [Repo]) -> Bool {
        guard let request = beginCreation(projects: projects) else { return false }
        hasBackgroundOperation = true
        Task {
            let result = await finishCreation(request)
            if let result, warningMessage == nil {
                toasts.show(.success, title: "Workspace ready", message: result.name)
            }
        }
        return true
    }

    @discardableResult
    public func create(projects: [Repo]) async -> ProjectWorkspace? {
        guard let request = beginCreation(projects: projects) else { return nil }
        return await finishCreation(request)
    }

    private func beginCreation(projects: [Repo]) -> WorkspaceCreateRequest? {
        guard !isCreating, lastCreated == nil else { return nil }
        guard canCreate, let project = projects.first(where: { $0.path == selectedProjectPath }) else {
            errorMessage = "Enter a valid name and select a Git or Plastic project."
            return nil
        }
        isCreating = true
        errorMessage = nil
        libraryWarning = nil
        saveWarning = nil
        let override = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkspaceCreateRequest(project: project, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            branchName: override.isEmpty ? nil : override, createNewBranch: createNewBranch, copyLibrary: copyLibrary,
            knownProjectPaths: repos.repos.map(\.path))
    }

    private func finishCreation(_ request: WorkspaceCreateRequest) async -> ProjectWorkspace? {
        defer { isCreating = false }
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
        createNewBranch = true
        hasBackgroundOperation = false
        errorMessage = nil
        libraryWarning = nil
        saveWarning = nil
        lastCreated = nil
        isInspecting = false
    }

    // MARK: - Silme (karar 51)

    public var isDeleting: Bool { deletingPath != nil }

    /// Yeni bir silme onayı açılırken önceki hata/force durumu sıfırlanır.
    public func beginDeleteFlow() {
        deleteError = nil
        canForceDelete = false
    }

    /// SCM kaydını ve klasörü kaldırır, ardından config kaydını düşürür.
    /// Başarısızlıkta kayıt yerinde kalır; hata dialogda gösterilir.
    @discardableResult
    public func deleteWorkspace(_ workspace: ProjectWorkspace, force: Bool) async -> Bool {
        guard !isDeleting, !(isCreating && lastCreated?.path == workspace.path) else { return false }
        deletingPath = workspace.path
        deleteError = nil
        defer { deletingPath = nil }
        do {
            try await service.remove(workspace, force: force)
        } catch {
            deleteError = error.localizedDescription
            canForceDelete = !force
            return false
        }
        await forgetRecord(workspace)
        toasts.show(.success, title: "Workspace deleted", message: workspace.name)
        return true
    }

    /// Yalnız kaydı düşürür; disk ve SCM'e dokunmaz (eksik workspace için).
    public func forgetWorkspace(_ workspace: ProjectWorkspace) async {
        guard !isDeleting else { return }
        await forgetRecord(workspace)
    }

    private func forgetRecord(_ workspace: ProjectWorkspace) async {
        pendingRecords.removeValue(forKey: workspace.path)
        if lastCreated?.path == workspace.path, !isCreating { clearForm() }
        do {
            try await config.updateConfig { $0.workspaces.removeAll { $0.path == workspace.path } }
            updateRecords(await config.config().workspaces)
        } catch {
            updateRecords(records.filter { $0.path != workspace.path })
            toasts.show(.error, title: "Workspace record could not be saved", message: error.localizedDescription)
        }
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
