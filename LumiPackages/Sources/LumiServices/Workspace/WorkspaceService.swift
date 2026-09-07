import Foundation
import LumiKit

public actor WorkspaceService: WorkspaceServicing {
    public static let commandTimeout: TimeInterval = 600
    private let runner: any ProcessRunning
    private let locator: any BinaryLocating
    private let workspaceRoot: URL
    private let libraryCopier = UnityLibraryCopier()
    private var creating = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var ownedDestinations = Set<String>()

    public init(
        runner: any ProcessRunning = SystemProcessRunner(),
        locator: any BinaryLocating = SystemBinaryLocator(),
        workspaceRoot: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("lumi/workspaces")
    ) {
        self.runner = runner
        self.locator = locator
        self.workspaceRoot = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
    }

    public func inspect(project: Repo) async throws -> WorkspaceSource {
        let path = Self.canonical(project.path)
        guard Self.isDirectory(path) else { throw WorkspaceFailure("Project folder is unavailable: \(path)") }
        let git = await runner.run("/usr/bin/git", arguments: ["rev-parse", "--show-toplevel"], currentDirectory: path, timeout: 10)
        if let git, git.exitCode == 0 {
            let root = Self.canonical(git.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            let revision = try await command("/usr/bin/git", ["rev-parse", "--verify", "HEAD^{commit}"], at: root)
            let branchResult = await runner.run("/usr/bin/git", arguments: ["symbolic-ref", "--short", "-q", "HEAD"], currentDirectory: root, timeout: 10)
            let branch = branchResult?.exitCode == 0 ? branchResult!.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return source(project: project, root: root, scm: .git, branch: branch, revision: revision)
        }
        guard let plasticRoot = Self.ancestor(with: ".plastic", of: path) else {
            return source(project: project, root: path, scm: .none)
        }
        guard let cm = await locator.locate("cm") else {
            throw WorkspaceFailure("Plastic SCM repository detected, but the cm CLI is unavailable. Install Unity Version Control to create workspaces.")
        }
        let info = try await command(cm, ["getworkspacefrompath", plasticRoot, "--format={wkpath}{tab}{type}{tab}{dynamic}", "--extended"], at: plasticRoot)
        let fields = info.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 3, Self.canonical(fields[0]) == plasticRoot,
              fields[1].lowercased() == "regular", ["false", "static"].contains(fields[2].lowercased()) else {
            throw WorkspaceFailure("Creation currently requires a regular Plastic workspace; Gluon and dynamic workspaces are not supported.")
        }
        let header = try await command(cm, ["status", "--header", "--machinereadable", "--fieldseparator=|"], at: plasticRoot)
        let metadata = try PlasticWorkspaceMetadata(header: header, selector: try Self.selector(at: plasticRoot))
        return source(project: project, root: plasticRoot, scm: .plastic, branch: metadata.branch,
                      revision: metadata.revision, repository: metadata.repository)
    }

    public func create(_ request: WorkspaceCreateRequest) async throws -> WorkspaceCreateResult {
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        let inspected = try await inspect(project: request.project)
        guard inspected.scm != .none else { throw WorkspaceFailure("Select a Git or Plastic SCM project to create a workspace.") }
        let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = WorkspaceName.slug(name)
        guard !folder.isEmpty, folder.utf8.count <= 120 else {
            throw WorkspaceFailure("Enter a workspace name containing letters or numbers (up to 120 bytes).")
        }
        let override = request.branchName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let branch: String
        if inspected.scm == .plastic, !request.createNewBranch {
            branch = inspected.branch
        } else {
            branch = override.isEmpty ? inspected.suggestedBranch(name: name) : override
        }
        let destination = URL(fileURLWithPath: inspected.destinationDirectory).appendingPathComponent(folder)
        try validateDestination(destination, source: inspected.projectPath, known: request.knownProjectPaths)
        if request.copyLibrary {
            guard inspected.isUnityProject, inspected.hasLibrary else { throw WorkspaceFailure("This project has no Unity Library to copy.") }
            if let reason = inspected.libraryCopyBlockedReason { throw WorkspaceFailure(reason) }
        }
        if inspected.scm == .git {
            guard !branch.hasPrefix("-") else { throw WorkspaceFailure("Branch names cannot start with a dash.") }
            _ = try await command("/usr/bin/git", ["check-ref-format", "--branch", branch], at: inspected.projectPath)
        } else {
            try Self.validatePlasticBranch(branch)
        }
        try prepareProjectDirectory(URL(fileURLWithPath: inspected.destinationDirectory), project: request.project)
        // Recheck after creating parents: a user-supplied symlink must never redirect the checkout.
        try validateDestination(destination, source: inspected.projectPath, known: request.knownProjectPaths)
        switch inspected.scm {
        case .git:
            _ = try await command("/usr/bin/git", ["worktree", "add", "--no-track", "-b", branch, destination.path, inspected.revision], at: inspected.projectPath, creatingAt: destination.path)
        case .plastic:
            guard let cm = await locator.locate("cm"), let repository = inspected.repositorySpec else {
                throw WorkspaceFailure("Plastic CLI or repository is unavailable.")
            }
            let spec = "br:\(branch)@\(repository)"
            if request.createNewBranch {
                _ = try await command(cm, ["branch", "create", spec, "--changeset=cs:\(inspected.revision)@\(repository)", "-c=Created by Lumi"], at: inspected.projectPath)
            }
            do {
                let workspaceName = "lumi-\(folder)-\(UUID().uuidString.prefix(8).lowercased())"
                _ = try await command(cm, ["workspace", "create", workspaceName, destination.path, repository], at: inspected.projectPath, creatingAt: destination.path)
                _ = try await command(cm, ["switch", spec, "--workspace=\(destination.path)", "--noinput"], at: destination.path, creatingAt: destination.path)
            } catch {
                let recovery = request.createNewBranch
                    ? "The branch \(spec) may remain. Inspect the workspace at \(destination.path) before retrying; Lumi has not removed it."
                    : "Inspect the workspace at \(destination.path) before retrying; Lumi did not create a new branch."
                throw WorkspaceFailure("\(error.localizedDescription)\n\(recovery)")
            }
        case .none: break
        }
        guard Self.isDirectory(destination.path) else { throw WorkspaceFailure("The command finished without creating \(destination.path).") }
        ownedDestinations.insert(Self.canonical(destination.path))
        var warning: String?
        if request.copyLibrary {
            do { try await copyLibrary(sourcePath: inspected.projectPath, workspacePath: destination.path) }
            catch { warning = "Workspace created, but Library was not copied: \(error.localizedDescription)" }
        }
        return WorkspaceCreateResult(workspace: ProjectWorkspace(projectPath: request.project.path,
            path: destination.path, name: name, branch: branch, scm: inspected.scm), warning: warning)
    }

    public func copyLibrary(sourcePath: String, workspacePath: String) async throws {
        let destination = Self.canonical(workspacePath)
        guard ownedDestinations.contains(destination), Self.contains(destination, in: workspaceRoot.path) else {
            throw WorkspaceFailure("Library can only be copied into a workspace created by this operation.")
        }
        try await libraryCopier.copy(sourcePath: sourcePath, workspacePath: workspacePath)
    }

    private func source(project: Repo, root: String, scm: WorkspaceSCM, branch: String = "", revision: String = "", repository: String? = nil) -> WorkspaceSource {
        let unity = Self.isDirectory(root + "/Assets") && FileManager.default.fileExists(atPath: root + "/ProjectSettings/ProjectVersion.txt")
        return WorkspaceSource(projectPath: root, scm: scm, branch: branch, revision: revision,
            repositorySpec: repository, destinationDirectory: destinationDirectory(for: project).path,
            isUnityProject: unity, hasLibrary: Self.isDirectory(root + "/Library"),
            libraryCopyBlockedReason: unity ? libraryCopier.blockedReason(sourcePath: root) : nil)
    }

    private func command(_ binary: String, _ arguments: [String], at path: String, creatingAt destination: String? = nil) async throws -> String {
        let timeout = destination == nil ? 30.0 : Self.commandTimeout
        let output = await runner.run(binary, arguments: arguments, currentDirectory: path, timeout: timeout)
        guard let output, output.exitCode == 0 else {
            let detail = output.map { $0.stderr.isEmpty ? $0.stdout : $0.stderr } ?? "Command timed out or could not be started."
            let recovery = destination.map { "\nInspect \($0) for a partial workspace before retrying." } ?? ""
            throw WorkspaceFailure("\((binary as NSString).lastPathComponent) \(arguments.prefix(2).joined(separator: " ")) failed: \(detail.trimmingCharacters(in: .whitespacesAndNewlines))\(recovery)")
        }
        return output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func destinationDirectory(for project: Repo) -> URL {
        let name = WorkspaceName.slug(project.name)
        let base = workspaceRoot.appendingPathComponent(name.isEmpty ? "project" : name)
        if !Self.entryExists(base.path) || Self.projectOwner(base) == Self.canonical(project.path) { return base }
        let hash = Self.canonical(project.path).utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return workspaceRoot.appendingPathComponent("\(name.isEmpty ? "project" : name)-\(String(hash, radix: 16).prefix(8))")
    }

    private func prepareProjectDirectory(_ directory: URL, project: Repo) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = directory.appendingPathComponent(".lumi-project")
        let identity = Self.canonical(project.path)
        if Self.entryExists(marker.path) {
            guard Self.projectOwner(directory) == identity else { throw WorkspaceFailure("Workspace project folder belongs to another project.") }
        } else {
            try Data(identity.utf8).write(to: marker, options: .withoutOverwriting)
        }
    }

    private func validateDestination(_ destination: URL, source: String, known: [String]) throws {
        let target = Self.canonical(destination.path)
        guard Self.contains(target, in: workspaceRoot.path), target != workspaceRoot.path,
              target == destination.standardizedFileURL.path else {
            throw WorkspaceFailure("Workspace destination must remain inside \(workspaceRoot.path); symbolic-link redirects are not allowed.")
        }
        let roots = [source] + known
        guard !roots.contains(where: { Self.contains(target, in: Self.canonical($0)) }) else {
            throw WorkspaceFailure("Workspace destination must be outside every source project and workspace.")
        }
        guard !Self.entryExists(destination.path) else { throw WorkspaceFailure("Workspace destination already exists: \(destination.path)") }
        guard Self.ancestor(with: ".git", of: target) == nil, Self.ancestor(with: ".plastic", of: target) == nil else {
            throw WorkspaceFailure("Workspace destination cannot be inside an existing repository.")
        }
    }

    private static func validatePlasticBranch(_ branch: String) throws {
        guard branch.hasPrefix("/"), branch != "/", !branch.hasSuffix("/"), !branch.contains("//"),
              !branch.contains(".."), !branch.contains("@"), !branch.contains(":"), !branch.contains("\""),
              !branch.contains("\\"), !branch.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw WorkspaceFailure("Enter a Plastic branch path such as /main/my-feature.")
        }
    }

    private static func selector(at root: String) throws -> String {
        let url = URL(fileURLWithPath: root).appendingPathComponent(".plastic/plastic.selector")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 < 1_048_576 else { throw WorkspaceFailure("Plastic selector is too large.") }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func acquire() async {
        if creating { await withCheckedContinuation { waiters.append($0) } }
        creating = true
    }
    private func release() {
        if waiters.isEmpty { creating = false } else { waiters.removeFirst().resume() }
    }
    private static func projectOwner(_ directory: URL) -> String? {
        try? String(contentsOf: directory.appendingPathComponent(".lumi-project"), encoding: .utf8)
    }
    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath().path
    }
    private static func contains(_ path: String, in root: String) -> Bool { path == root || path.hasPrefix(root + "/") }
    private static func entryExists(_ path: String) -> Bool { (try? FileManager.default.attributesOfItem(atPath: path)) != nil }
    private static func isDirectory(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
    }
    private static func ancestor(with marker: String, of path: String) -> String? {
        var current = URL(fileURLWithPath: path).standardizedFileURL
        while current.path != "/" {
            if entryExists(current.appendingPathComponent(marker).path) { return canonical(current.path) }
            current.deleteLastPathComponent()
        }
        return nil
    }
}
