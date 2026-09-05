import Foundation
import LumiKit

/// Git CLI + porcelain parse servisi (design/02 §4).
/// CLI yaklaşımı bilinçli: kullanıcının git config/hook/credential dünyasıyla
/// otomatik uyumlu (Electron notu 3). Worktree/checkout/pull/push/stash
/// kapsam DIŞI (YAGNI).
///
/// Refactor 3.10: bu tip artık yalnız ORKESTRASYON yapar — komut koşumu
/// `GitCommandRunner`, parse `GitPorcelainParser`, path doğrulaması
/// `RepoPathGuard` içindedir.
public struct GitService: GitServicing {
    static let gitExecutable = GitCommandRunner.gitExecutable
    static let commandTimeout = GitCommandRunner.commandTimeout

    private let commands: GitCommandRunner
    private let guardian: RepoPathGuard
    /// `gh` (GitHub CLI) varlığı için — git'in kendisi `GitCommandRunner`dan
    /// geçer, komşu CLI'lar PATH çözümlemesinden.
    private let locator: any BinaryLocating

    public init(
        runner: any ProcessRunning = SystemProcessRunner(),
        pathGuard: RepoPathGuard = RepoPathGuard(),
        locator: any BinaryLocating = SystemBinaryLocator()
    ) {
        self.commands = GitCommandRunner(runner: runner)
        self.guardian = pathGuard
        self.locator = locator
    }

    public init(
        commands: GitCommandRunner,
        pathGuard: RepoPathGuard = RepoPathGuard(),
        locator: any BinaryLocating = SystemBinaryLocator()
    ) {
        self.commands = commands
        self.guardian = pathGuard
        self.locator = locator
    }

    // MARK: - Branch / commit log

    public func branches(repoPath: String) async -> [GitBranch] {
        let output = await commands.run(["branch", "--list", "--no-color"], in: repoPath)
        guard let output, output.exitCode == 0 else {
            commands.logQuietFailure("branches", output)
            return []
        }
        return GitPorcelainParser.parseBranches(output.stdout)
    }

    public func commits(repoPath: String, branch: String?) async -> [GitCommit] {
        var arguments = [
            "log", "--max-count=50",
            "--pretty=format:%H%x1f%h%x1f%an%x1f%aI%x1f%s",
        ]
        if let branch {
            // Default branch YALNIZ gerektiğinde ve tek `for-each-ref` ile
            // hesaplanır: eskiden her `commits` çağrısı ayrıca tam bir
            // `git branch --list` koşturuyordu (N branch → 2N process).
            let defaultBranch = await defaultBranch(in: repoPath)
            if let defaultBranch, branch != defaultBranch {
                // Kritik UX: yalnız branch'e özgü commit'ler
                arguments.append("\(defaultBranch)..\(branch)")
            } else {
                arguments.append(branch)
            }
        }

        let output = await commands.run(arguments, in: repoPath)
        guard let output, output.exitCode == 0 else {
            commands.logQuietFailure("commits", output)
            return []
        }
        return GitPorcelainParser.parseCommits(output.stdout)
    }

    /// Karar 40: History sekmesinin tek log'u. `-z` NUL çerçevelemesi mesaj
    /// içindeki satır sonlarını korur; `--decorate=full` ref'leri tam adla
    /// verir (kullanıcının `log.decorate` config'i çıktıyı kısaltamaz).
    public func history(repoPath: String, limit: Int) async -> [GitCommit] {
        guard limit > 0 else { return [] }
        let output = await commands.run(
            [
                "log", "--max-count=\(limit)", "-z", "--topo-order", "--decorate=full",
                "--pretty=format:%H%x1f%h%x1f%an%x1f%aI%x1f%P%x1f%D%x1f%s", "HEAD",
            ],
            in: repoPath
        )
        guard let output, output.exitCode == 0 else {
            commands.logQuietFailure("history", output)
            return []
        }
        return GitPorcelainParser.parseHistory(output.stdout)
    }

    public func remoteURL(repoPath: String) async -> String? {
        let output = await commands.run(["remote", "get-url", "origin"], in: repoPath)
        guard let output, output.exitCode == 0 else {
            commands.logQuietFailure("remoteURL", output)
            return nil
        }
        let trimmed = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func isGitHubCLIAvailable() async -> Bool {
        await locator.locate("gh") != nil
    }

    /// Üç hafif komut: upstream adı (`@{u}` yoksa exit≠0 → yayınlanmamış),
    /// ileri/geri sayısı ve `diff --shortstat HEAD` (staged+unstaged; untracked
    /// satırları git'in kendisi de saymaz).
    public func branchSummary(repoPath: String) async -> GitBranchSummary? {
        guard let stat = await commands.run(["diff", "--shortstat", "HEAD"], in: repoPath), stat.exitCode == 0 else {
            return nil
        }
        let lines = GitPorcelainParser.parseShortStat(stat.stdout)
        let upstreamOutput = await commands.run(
            ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"], in: repoPath
        )
        guard let upstreamOutput, upstreamOutput.exitCode == 0 else {
            return GitBranchSummary(insertions: lines.insertions, deletions: lines.deletions)
        }
        let upstream = upstreamOutput.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let counts = await commands.run(["rev-list", "--left-right", "--count", "HEAD...@{upstream}"], in: repoPath)
        let aheadBehind = counts.flatMap { $0.exitCode == 0 ? GitPorcelainParser.parseAheadBehind($0.stdout) : nil }
        return GitBranchSummary(
            upstream: upstream.isEmpty ? nil : upstream,
            ahead: aheadBehind?.ahead ?? 0,
            behind: aheadBehind?.behind ?? 0,
            insertions: lines.insertions,
            deletions: lines.deletions
        )
    }

    /// Tek `for-each-ref` ile yalnız iki aday ref'i sorar — `branch --list`'in
    /// tüm branch'leri listeleyip parse etmesine gerek yok.
    private func defaultBranch(in repoPath: String) async -> String? {
        let output = await commands.run(
            ["for-each-ref", "--format=%(refname:short)", "refs/heads/main", "refs/heads/master"],
            in: repoPath
        )
        guard let output, output.exitCode == 0 else { return nil }
        return GitPorcelainParser.defaultBranch(fromRefOutput: output.stdout)
    }

    // MARK: - Status / commit

    public func status(repoPath: String) async -> [GitFileChange] {
        let output = await commands.run(["status", "--porcelain", "--untracked-files=all", "-z"], in: repoPath)
        guard let output, output.exitCode == 0 else {
            commands.logQuietFailure("status", output)
            return []
        }
        return GitPorcelainParser.parseStatusZeroTerminated(output.stdout)
    }

    public func commit(repoPath: String, message: String, files: [String]) async throws {
        guard !files.isEmpty else {
            throw LumiError.gitFailed(operation: "commit", detail: "No files selected")
        }
        for file in files {
            _ = try resolveInsideRepo(repoPath, file)
        }

        // Detay İLK koşunun stderr'inden gelir: hata yolunda `add`'i ikinci kez
        // çalıştırmak yan etkiyi tekrarlar ve gereksiz bir process daha açardı.
        let addOutput = await commands.run(["add", "--"] + files, in: repoPath)
        guard let addOutput, addOutput.exitCode == 0 else {
            throw LumiError.gitFailed(
                operation: "add",
                detail: addOutput.map { String($0.stderr.prefix(500)) } ?? "timeout"
            )
        }
        guard let commitOutput = await commands.run(
            ["commit", "-m", message, "--"] + files,
            in: repoPath
        ) else {
            throw LumiError.gitFailed(operation: "commit", detail: "timeout")
        }
        guard commitOutput.exitCode == 0 else {
            let detail = commitOutput.stderr.isEmpty ? commitOutput.stdout : commitOutput.stderr
            throw LumiError.gitFailed(
                operation: "commit",
                detail: String(detail.prefix(500))
            )
        }
    }

    // MARK: - Dosya içerikleri / diff'ler

    /// Metin önizlemesinin üst sınırı: NSTextView'a bundan büyük tek parça
    /// metin basmak ana thread'i kilitler (video dosyası crash'inin ikinci yüzü).
    public static let maxTextPreviewBytes = 8 * 1024 * 1024
    /// NUL sniff penceresi — uzantısı yanıltan binary'ler için (git'in kendi
    /// binary sezgisiyle aynı yaklaşım).
    static let binarySniffBytes = 8 * 1024

    public func readFile(repoPath: String, file: String) async throws -> String {
        let absolute = try resolveInsideRepo(repoPath, file)
        guard let data = FileManager.default.contents(atPath: absolute) else {
            throw LumiError.fileOperationFailed(path: file, detail: "file could not be read")
        }
        guard data.count <= Self.maxTextPreviewBytes else {
            let megabytes = Double(data.count) / (1024 * 1024)
            throw LumiError.fileOperationFailed(
                path: file,
                detail: String(format: "file is too large to preview (%.1f MB)", megabytes)
            )
        }
        guard !Self.looksBinary(data) else {
            throw LumiError.fileOperationFailed(
                path: file,
                detail: "binary file cannot be previewed as text"
            )
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// İlk 8 KB'de NUL byte varsa binary sayılır.
    static func looksBinary(_ data: Data) -> Bool {
        data.prefix(Self.binarySniffBytes).contains(0)
    }

    public func fileDiff(repoPath: String, file: String) async throws -> UnifiedDiff {
        _ = try resolveInsideRepo(repoPath, file)

        let tracked = await commands.run(["ls-files", "--", file], in: repoPath)
        let isTracked = (tracked?.exitCode == 0) && !(tracked?.stdout.isEmpty ?? true)

        if isTracked {
            guard let output = await commands.run(["diff", "HEAD", "--", file], in: repoPath),
                  output.exitCode == 0 else {
                throw LumiError.gitFailed(operation: "diff", detail: "git diff failed for \(file)")
            }
            return UnifiedDiffParser.parse(output.stdout, filePath: file)
        }

        // Untracked: /dev/null'a karşı tamamı-ekleme diff'i (exit 1 = fark var, hata değil)
        guard let output = await commands.run(
            ["diff", "--no-index", "--", "/dev/null", file],
            in: repoPath
        ) else {
            throw LumiError.gitFailed(operation: "diff", detail: "timeout")
        }
        return UnifiedDiffParser.parse(output.stdout, filePath: file)
    }

    public func commitFiles(repoPath: String, sha: String) async -> [CommitFile] {
        let output = await commands.run(
            ["diff-tree", "--no-commit-id", "-r", "--name-status", "--root", sha],
            in: repoPath
        )
        guard let output, output.exitCode == 0 else {
            commands.logQuietFailure("commitFiles", output)
            return []
        }
        return GitPorcelainParser.parseDiffTree(output.stdout)
    }

    public func commitFileDiff(repoPath: String, sha: String, file: String) async throws -> UnifiedDiff {
        _ = try resolveInsideRepo(repoPath, file)
        // `git show` ilk (root) commit'te de çalışır — `sha^` parent sorunu yok
        guard let output = await commands.run(
            ["show", "--pretty=format:", "--patch", sha, "--", file],
            in: repoPath
        ), output.exitCode == 0 else {
            throw LumiError.gitFailed(operation: "show", detail: "diff unavailable for \(file) @ \(sha)")
        }
        return UnifiedDiffParser.parse(output.stdout, filePath: file)
    }

    // MARK: - Görsel önizleme (karar 21)

    /// Tek bir tarafın bellek sınırı: bunun üstündeki blob yüklenmez, UI
    /// "too large" gösterir (viewer'ın 100MB'lık bir PSD'yi RAM'e almaması için).
    static let maxImagePreviewBytes = 20 * 1024 * 1024

    private struct BlobResult {
        let data: Data?
        let isTooLarge: Bool

        static let missing = BlobResult(data: nil, isTooLarge: false)
    }

    public func imagePreview(repoPath: String, file: String, sha: String?) async -> ImagePreview {
        guard let absolute = try? resolveInsideRepo(repoPath, file) else {
            fputs("[lumi-git] imagePreview reddedildi (repo dışı path): \(file)\n", stderr)
            return ImagePreview(filePath: file, before: nil, after: nil)
        }
        // Commit modunda iki taraf da blob; working-tree modunda "after" disktir.
        let before: BlobResult
        let after: BlobResult
        if let sha {
            before = await blob(repoPath: repoPath, revision: "\(sha)^", file: file)
            after = await blob(repoPath: repoPath, revision: sha, file: file)
        } else {
            before = await blob(repoPath: repoPath, revision: "HEAD", file: file)
            after = Self.readCapped(absolute)
        }
        return ImagePreview(
            filePath: file,
            before: before.data,
            after: after.data,
            isTooLarge: before.isTooLarge || after.isTooLarge
        )
    }

    /// `git show <revision>:<path>` — path repo köküne göredir (cwd = repo kökü).
    /// Eksik taraf (root commit'in parent'ı, eklenen/silinen dosya) BEKLENEN
    /// durumdur: sessizce nil döner, log gürültüsü üretilmez.
    private func blob(repoPath: String, revision: String, file: String) async -> BlobResult {
        let output = await commands.runRaw(["show", "\(revision):\(file)"], in: repoPath)
        guard let output, output.exitCode == 0, !output.stdout.isEmpty else { return .missing }
        guard output.stdout.count <= Self.maxImagePreviewBytes else {
            return BlobResult(data: nil, isTooLarge: true)
        }
        return BlobResult(data: output.stdout, isTooLarge: false)
    }

    /// Disk içeriği — boyut önce attribute'tan okunur (sınır üstü dosya hiç
    /// belleğe alınmaz).
    private static func readCapped(_ absolutePath: String) -> BlobResult {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: absolutePath),
              let size = attributes[.size] as? Int else { return .missing }
        guard size <= maxImagePreviewBytes else { return BlobResult(data: nil, isTooLarge: true) }
        guard let data = FileManager.default.contents(atPath: absolutePath), !data.isEmpty else {
            return .missing
        }
        return BlobResult(data: data, isTooLarge: false)
    }

    // MARK: - Path traversal guard (karar 11: TÜM path'lerde)

    func resolveInsideRepo(_ repoPath: String, _ relativePath: String) throws -> String {
        try guardian.resolve(repoPath: repoPath, relativePath: relativePath)
    }
}
