import Foundation
import LumiKit

public actor WorkspaceService: WorkspaceServicing {
    public static let commandTimeout: TimeInterval = 600
    /// Yönetilen workspace kökü (karar 48); keşif servisi de aynı kökü kullanır.
    public static let defaultRoot = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("lumi/workspaces")
    private let runner: any ProcessRunning
    private let locator: any BinaryLocating
    private let workspaceRoot: URL
    private let libraryCopier = UnityLibraryCopier()
    private var creating = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var ownedDestinations = Set<String>()
    /// Dal listesi önbelleği (karar 58): `cm find` sunucuya gidiyor (~1.5 sn),
    /// aynı dialog içinde her açılışta yeniden sorulmasın.
    private var branchCache: [String: (fetchedAt: Date, branches: [WorkspaceBranch])] = [:]
    public static let branchCacheTTL: TimeInterval = 60
    /// `0` → sınırsız: tüm dallar çekilir. Ölçüm (word-puzzle, 126 dal):
    /// tam liste ~2,3 sn, son 20 ~1,6 sn — aradaki fark, listede aranabilmenin
    /// yanında önemsiz (karar 58).
    public static let defaultBranchLimit = 0

    public init(
        runner: any ProcessRunning = SystemProcessRunner(),
        locator: any BinaryLocating = SystemBinaryLocator(),
        workspaceRoot: URL = WorkspaceService.defaultRoot
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

    /// Karar 58. Git'te `for-each-ref` (yerel, anlık), Plastic'te `cm find`
    /// (sunucu, ~1.5 sn). Sonuç `branchCacheTTL` boyunca saklanır.
    public func branches(project: Repo, limit: Int = WorkspaceService.defaultBranchLimit) async throws -> [WorkspaceBranch] {
        let count = limit <= 0 ? 0 : min(limit, Self.branchHardCap)
        let source = try await inspect(project: project)
        let key = "\(source.projectPath)#\(count)"
        if let cached = branchCache[key], Date().timeIntervalSince(cached.fetchedAt) < Self.branchCacheTTL {
            return cached.branches
        }
        let names: [String]
        switch source.scm {
        case .git:
            let output = try await command("/usr/bin/git", [
                "for-each-ref", "--sort=-committerdate",
            ] + (count > 0 ? ["--count=\(count)"] : []) + [
                "--format=%(refname:short)", "refs/heads",
            ], at: source.projectPath)
            names = output.split(separator: "\n").map(String.init)
        case .plastic:
            guard let cm = await locator.locate("cm") else {
                throw WorkspaceFailure("Plastic SCM cm CLI is unavailable, so branches cannot be listed.")
            }
            names = try await plasticBranches(cm: cm, at: source.projectPath, count: count)
        case .none:
            names = []
        }
        var seen = Set<String>()
        let branches = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .map(WorkspaceBranch.init(name:))
        branchCache[key] = (Date(), branches)
        return branches
    }

    /// `cm find` .NET çalışma zamanını ayağa kaldırıp sunucuya gidiyor; ölçüm
    /// ~1.6 sn, ağ yavaşken payı olsun diye 30 sn.
    public static let branchQueryTimeout: TimeInterval = 30

    /// Sınırsız istense bile arayüz sonsuz satır çizmesin.
    static let branchHardCap = 5000

    /// Son changeset'lerden dal çıkarırken taranan changeset sayısı: dal
    /// başına ortalama ~25 changeset düşüyor (word-puzzle ölçümü: 500
    /// changeset → 30 ayrı dal). Sorgunun maliyeti limitten bağımsız (~1,4 sn).
    static let changesetScanFactor = 25
    static let changesetScanRange = 200...2000

    /// Plastic dal listesi (karar 58).
    ///
    /// `branch` nesnesinin `date` alanı OLUŞTURMA tarihidir ve `order by`
    /// yalnız `date`/`branchname` kabul ediyor; bu yüzden tek başına
    /// "son N dal" sorgusu, eski açılmış ama hâlâ işlenen dalları
    /// (ör. `/main/sand-blocks/release`) kaçırıyordu. Git'teki
    /// `--sort=-committerdate` semantiğini yakalamak için son changeset'lerin
    /// dallarını da çekip iki listeyi tarihe göre birleştiriyoruz: aktif
    /// dallar + henüz changeset'i olmayan yeni dallar.
    private func plasticBranches(cm: String, at path: String, count: Int) async throws -> [String] {
        let scan = count <= 0
            ? Self.changesetScanRange.upperBound
            : min(max(count * Self.changesetScanFactor, Self.changesetScanRange.lowerBound), Self.changesetScanRange.upperBound)
        let limitClause = count > 0 ? " limit \(count)" : ""
        async let created = plasticBranchRows(cm: cm, at: path, query: "branches order by date desc\(limitClause)", field: "name")
        async let active = plasticBranchRows(cm: cm, at: path, query: "changesets order by date desc limit \(scan)", field: "branch")
        var latest: [String: String] = [:]
        for (name, date) in try await created + active where latest[name].map({ $0 < date }) ?? true {
            latest[name] = date
        }
        let ordered = latest
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map(\.key)
        return count > 0 ? Array(ordered.prefix(count)) : ordered
    }

    /// `<tarih>|<ad>` satırları. `{tab}` dal nesnesinde geçerli bir alan
    /// değil ("The field tab is not valid for the specified object type"),
    /// bu yüzden ayraç "|"; tarih başa alınır ki İLK "|" ayırsın (dal adında
    /// "|" bulunabilir, sabit biçimli tarihte bulunamaz). Tarih sıralanabilir
    /// olsun diye `--dateformat` sabitlenir (yerel biçim makineye göre değişir).
    private func plasticBranchRows(cm: String, at path: String, query: String, field: String) async throws -> [(String, String)] {
        let output = try await command(cm, [
            "find", query, "--format={date}|{\(field)}",
            "--dateformat=yyyy-MM-dd HH:mm:ss", "--nototal",
        ], at: path, timeout: Self.branchQueryTimeout)
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let name = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : (name, parts[0])
        }
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
        let base = request.baseBranch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let branch: String
        switch request.branchMode {
        case .current:
            // Git bir dalı iki worktree'de aynı anda checkout edemez.
            guard inspected.scm == .plastic else {
                throw WorkspaceFailure("Git cannot check out the current branch in a second worktree; choose an existing or a new branch.")
            }
            branch = inspected.branch
        case .existing:
            guard !override.isEmpty else { throw WorkspaceFailure("Select the branch to check out.") }
            branch = override
        case .new:
            // Plastic'te hiyerarşi taban daldan gelir; yazılan ad tek parçadır.
            let leaf = override.isEmpty ? WorkspaceName.slug(name) : override
            guard inspected.scm != .plastic || !leaf.contains("/") else {
                throw WorkspaceFailure("A Plastic branch name cannot contain \"/\"; the hierarchy comes from the base branch.")
            }
            branch = inspected.fullBranch(leaf: leaf, base: base.isEmpty ? nil : base)
        }
        let destination = URL(fileURLWithPath: inspected.destinationDirectory).appendingPathComponent(folder)
        try validateDestination(destination, source: inspected.projectPath, known: request.knownProjectPaths)
        if request.copyLibrary {
            guard inspected.isUnityProject, inspected.hasLibrary else { throw WorkspaceFailure("This project has no Unity Library to copy.") }
            if let reason = inspected.libraryCopyBlockedReason { throw WorkspaceFailure(reason) }
        }
        if inspected.scm == .git {
            guard !branch.hasPrefix("-"), !base.hasPrefix("-") else { throw WorkspaceFailure("Branch names cannot start with a dash.") }
            _ = try await command("/usr/bin/git", ["check-ref-format", "--branch", branch], at: inspected.projectPath)
        } else {
            try Self.validatePlasticBranch(branch)
            if request.branchMode == .new, !base.isEmpty { try Self.validatePlasticBranch(base) }
        }
        try prepareProjectDirectory(URL(fileURLWithPath: inspected.destinationDirectory), project: request.project)
        // Recheck after creating parents: a user-supplied symlink must never redirect the checkout.
        try validateDestination(destination, source: inspected.projectPath, known: request.knownProjectPaths)
        switch inspected.scm {
        case .git:
            if request.branchMode == .existing {
                _ = try await command("/usr/bin/git", ["worktree", "add", destination.path, branch], at: inspected.projectPath, creatingAt: destination.path)
            } else {
                // Yeni dal, seçilen taban dalın ucundan (seçilmediyse mevcut HEAD).
                let start = base.isEmpty ? inspected.revision
                    : try await command("/usr/bin/git", ["rev-parse", "--verify", "\(base)^{commit}"], at: inspected.projectPath)
                _ = try await command("/usr/bin/git", ["worktree", "add", "--no-track", "-b", branch, destination.path, start], at: inspected.projectPath, creatingAt: destination.path)
            }
        case .plastic:
            guard let cm = await locator.locate("cm"), let repository = inspected.repositorySpec else {
                throw WorkspaceFailure("Plastic CLI or repository is unavailable.")
            }
            let spec = "br:\(branch)@\(repository)"
            if request.branchMode == .new {
                let changeset = base.isEmpty || base == inspected.branch ? inspected.revision
                    : try await headChangeset(of: base, cm: cm, at: inspected.projectPath)
                _ = try await command(cm, ["branch", "create", spec, "--changeset=cs:\(changeset)@\(repository)", "-c=Created by Lumi"], at: inspected.projectPath)
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
            do {
                let skipped = try await copyLibraryReportingSkips(sourcePath: inspected.projectPath, workspacePath: destination.path)
                if skipped > 0 {
                    warning = "Library copied while Unity was writing to it; \(skipped) file(s) were skipped and Unity will regenerate them on first import."
                }
            } catch { warning = "Workspace created, but Library was not copied: \(error.localizedDescription)" }
        }
        return WorkspaceCreateResult(workspace: ProjectWorkspace(projectPath: request.project.path,
            path: destination.path, name: name, branch: branch, scm: inspected.scm), warning: warning)
    }

    /// Karar 49. Sıra: SCM kaydı → artık klasör → sahiplik seti. Hedef, kanonik
    /// yolla `workspaceRoot` içinde kalmak ve kaynak projeyi kapsamamak zorunda;
    /// aksi hâlde hiçbir komut çalışmaz. Klasör diskte yoksa yalnız SCM
    /// metadata'sı temizlenir (`git worktree prune`).
    public func remove(_ workspace: ProjectWorkspace, force: Bool) async throws {
        let target = Self.canonical(workspace.path)
        guard Self.contains(target, in: workspaceRoot.path), target != workspaceRoot.path else {
            throw WorkspaceFailure("Only workspaces inside \(workspaceRoot.path) can be deleted; \(workspace.path) is outside the managed root.")
        }
        let project = Self.canonical(workspace.projectPath)
        guard !Self.contains(project, in: target) else {
            throw WorkspaceFailure("Refusing to delete a folder that contains the source project.")
        }
        let exists = Self.entryExists(target)
        switch workspace.scm {
        case .git:
            guard Self.isDirectory(project) else { break }
            if exists {
                let arguments = ["worktree", "remove"] + (force ? ["--force"] : []) + [target]
                _ = try await command("/usr/bin/git", arguments, at: project, timeout: Self.commandTimeout)
            } else {
                _ = try await command("/usr/bin/git", ["worktree", "prune"], at: project)
            }
        case .plastic:
            guard exists else { break }
            if let cm = await locator.locate("cm") {
                let cwd = Self.isDirectory(project) ? project : workspaceRoot.path
                _ = try await command(cm, ["workspace", "delete", target], at: cwd, timeout: Self.commandTimeout)
            } else if !force {
                throw WorkspaceFailure("Plastic SCM cm CLI is unavailable, so the workspace registration cannot be removed. Force Delete removes only the folder.")
            }
        case .none:
            break
        }
        if Self.entryExists(target) {
            do { try FileManager.default.trashItem(at: URL(fileURLWithPath: target), resultingItemURL: nil) }
            catch { throw WorkspaceFailure("Workspace folder could not be moved to Trash: \(error.localizedDescription)") }
        }
        ownedDestinations.remove(target)
    }

    public func copyLibrary(sourcePath: String, workspacePath: String) async throws {
        _ = try await copyLibraryReportingSkips(sourcePath: sourcePath, workspacePath: workspacePath)
    }

    /// Atlanan dosya sayısını döndürür: Unity açıkken kopyalamaya izin verilir
    /// (karar 58), o sırada yazılan tek tük dosya okunamazsa kopya sürer.
    @discardableResult
    private func copyLibraryReportingSkips(sourcePath: String, workspacePath: String) async throws -> Int {
        let destination = Self.canonical(workspacePath)
        guard ownedDestinations.contains(destination), Self.contains(destination, in: workspaceRoot.path) else {
            throw WorkspaceFailure("Library can only be copied into a workspace created by this operation.")
        }
        return try await libraryCopier.copy(sourcePath: sourcePath, workspacePath: workspacePath)
    }

    private func source(project: Repo, root: String, scm: WorkspaceSCM, branch: String = "", revision: String = "", repository: String? = nil) -> WorkspaceSource {
        let unity = Self.isDirectory(root + "/Assets") && FileManager.default.fileExists(atPath: root + "/ProjectSettings/ProjectVersion.txt")
        return WorkspaceSource(projectPath: root, scm: scm, branch: branch, revision: revision,
            repositorySpec: repository, destinationDirectory: destinationDirectory(for: project).path,
            isUnityProject: unity, hasLibrary: Self.isDirectory(root + "/Library"),
            libraryCopyBlockedReason: unity ? libraryCopier.blockedReason(sourcePath: root) : nil,
            libraryCopyWarning: unity ? libraryCopier.activeEditorWarning(sourcePath: root) : nil)
    }

    private func command(_ binary: String, _ arguments: [String], at path: String, creatingAt destination: String? = nil,
                         timeout explicitTimeout: TimeInterval? = nil) async throws -> String {
        let timeout = explicitTimeout ?? (destination == nil ? 30.0 : Self.commandTimeout)
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
        // Yalnız yönetilen kök ile hedef arasına bakılır: `workspaceRoot` ÜSTÜNDEKİ
        // `.git`/`.plastic` girdileri (ev dizinindeki dotfile repo'su, Plastic
        // istemcisinin `~/.plastic` klasörü) Lumi'yi ilgilendirmez ve eskiden o
        // makinelerde her workspace oluşturmayı bloke ediyordu.
        guard Self.ancestor(with: ".git", of: target, stoppingAt: workspaceRoot.path) == nil,
              Self.ancestor(with: ".plastic", of: target, stoppingAt: workspaceRoot.path) == nil else {
            throw WorkspaceFailure("Workspace destination cannot be inside an existing repository.")
        }
    }

    /// Taban dalın ucundaki changeset (karar 58). Dal adı `find` sorgusuna
    /// gömüldüğü için önce `validatePlasticBranch`ten geçmiş olmalıdır.
    private func headChangeset(of branch: String, cm: String, at path: String) async throws -> String {
        let output = try await command(cm, [
            "find", "changesets where branch = 'br:\(branch)' order by changesetid desc limit 1",
            "--format={changesetid}", "--nototal",
        ], at: path, timeout: Self.branchQueryTimeout)
        let changeset = output.split(separator: "\n").map(String.init).last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !changeset.isEmpty, changeset.allSatisfy(\.isNumber) else {
            throw WorkspaceFailure("Branch \(branch) has no changeset to start from.")
        }
        return changeset
    }

    private static func validatePlasticBranch(_ branch: String) throws {
        guard branch.hasPrefix("/"), branch != "/", !branch.hasSuffix("/"), !branch.contains("//"),
              !branch.contains(".."), !branch.contains("@"), !branch.contains(":"), !branch.contains("\""),
              !branch.contains("'"),
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
    private static func canonical(_ path: String) -> String { CanonicalPath.of(path) }
    private static func contains(_ path: String, in root: String) -> Bool { path == root || path.hasPrefix(root + "/") }
    private static func entryExists(_ path: String) -> Bool { (try? FileManager.default.attributesOfItem(atPath: path)) != nil }
    private static func isDirectory(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
    }
    /// `stop` dizini de taranır, üstüne çıkılmaz; varsayılan "/" ile kök dizine
    /// kadar yürür.
    private static func ancestor(with marker: String, of path: String, stoppingAt stop: String = "/") -> String? {
        var current = URL(fileURLWithPath: path).standardizedFileURL
        while true {
            if entryExists(current.appendingPathComponent(marker).path) { return canonical(current.path) }
            if current.path == stop || current.path == "/" { return nil }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { return nil }
            current = parent
        }
    }
}
