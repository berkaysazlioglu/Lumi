import Foundation
import LumiKit

/// Git CLI + porcelain parse servisi (spec/12, design/02 §4).
/// CLI yaklaşımı bilinçli: kullanıcının git config/hook/credential dünyasıyla
/// otomatik uyumlu (spec/12 Electron notu 3). Worktree/checkout/pull/push/stash
/// kapsam DIŞI (YAGNI — spec/12).
public struct GitService: GitServicing {
    static let gitExecutable = "/usr/bin/git"
    static let commandTimeout: TimeInterval = 20

    public init() {}

    private func runGit(
        _ arguments: [String],
        in repoPath: String,
        input: Data? = nil
    ) async -> ProcessRunner.Output? {
        await ProcessRunner.run(
            Self.gitExecutable,
            arguments: arguments,
            currentDirectory: repoPath,
            standardInput: input,
            timeout: Self.commandTimeout
        )
    }

    private func logQuietFailure(_ operation: String, _ output: ProcessRunner.Output?) {
        // "Boş ve sessiz" parite (spec/12): UI'ya hata sızdırılmaz ama iz bırakılır
        let detail = output.map { "exit \($0.exitCode): \($0.stderr.prefix(200))" } ?? "timeout/launch failure"
        fputs("[lumi-git] \(operation) başarısız (sessiz): \(detail)\n", stderr)
    }

    // MARK: - Branch / commit log

    public func branches(repoPath: String) async -> [GitBranch] {
        guard let output = await runGit(["branch", "--list", "--no-color"], in: repoPath),
              output.exitCode == 0 else {
            logQuietFailure("branches", nil)
            return []
        }
        return output.stdout.split(separator: "\n").compactMap { line in
            guard line.count > 2 else { return nil }
            let isCurrent = line.hasPrefix("* ")
            let name = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.hasPrefix("(") else { return nil } // detached HEAD satırı
            return GitBranch(name: name, isCurrent: isCurrent)
        }
    }

    public func commits(repoPath: String, branch: String?) async -> [GitCommit] {
        let branchList = await branches(repoPath: repoPath)
        let defaultBranch = Self.defaultBranch(from: branchList)

        var arguments = [
            "log", "--max-count=50",
            "--pretty=format:%H%x1f%h%x1f%an%x1f%aI%x1f%s",
        ]
        if let branch {
            if let defaultBranch, branch != defaultBranch {
                // Kritik UX (spec/12 §2): yalnız branch'e özgü commit'ler
                arguments.append("\(defaultBranch)..\(branch)")
            } else {
                arguments.append(branch)
            }
        }

        guard let output = await runGit(arguments, in: repoPath), output.exitCode == 0 else {
            logQuietFailure("commits", nil)
            return []
        }
        let dateParser = ISO8601DateFormatter()
        return output.stdout.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\u{1f}", maxSplits: 4, omittingEmptySubsequences: false)
            guard parts.count == 5 else { return nil }
            return GitCommit(
                hash: String(parts[0]),
                shortHash: String(parts[1]),
                message: String(parts[4]),
                author: String(parts[2]),
                date: dateParser.date(from: String(parts[3])) ?? Date(timeIntervalSince1970: 0)
            )
        }
    }

    static func defaultBranch(from branches: [GitBranch]) -> String? {
        if branches.contains(where: { $0.name == "main" }) { return "main" }
        if branches.contains(where: { $0.name == "master" }) { return "master" }
        return nil
    }

    // MARK: - Status / commit

    public func status(repoPath: String) async -> [GitFileChange] {
        guard let output = await runGit(["status", "--porcelain"], in: repoPath),
              output.exitCode == 0 else {
            logQuietFailure("status", nil)
            return []
        }
        return output.stdout.split(separator: "\n").compactMap { line in
            Self.parseStatusLine(String(line))
        }
    }

    /// Porcelain v1 satırı → sadeleştirilmiş statü (spec/12 §4): index+worktree
    /// kodları tek statüye iner; rename'de `to` path'i alınır.
    static func parseStatusLine(_ line: String) -> GitFileChange? {
        guard line.count >= 4 else { return nil }
        let indexStatus = line[line.startIndex]
        let worktreeStatus = line[line.index(after: line.startIndex)]
        var path = String(line.dropFirst(3))
        if let arrow = path.range(of: " -> ") {
            path = String(path[arrow.upperBound...])
        }
        if path.hasPrefix("\""), path.hasSuffix("\""), path.count >= 2 {
            path = String(path.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }

        let status: FileChangeStatus
        if indexStatus == "?" {
            status = .untracked
        } else if indexStatus == "R" || worktreeStatus == "R" {
            status = .renamed
        } else if indexStatus == "D" || worktreeStatus == "D" {
            status = .deleted
        } else if indexStatus == "A" {
            status = .added
        } else {
            status = .modified
        }
        return GitFileChange(path: path, status: status)
    }

    public func commit(repoPath: String, message: String, files: [String]) async throws {
        guard !files.isEmpty else {
            throw LumiError.gitFailed(operation: "commit", detail: "No files selected")
        }
        for file in files {
            _ = try resolveInsideRepo(repoPath, file)
        }

        guard let addOutput = await runGit(["add", "--"] + files, in: repoPath),
              addOutput.exitCode == 0 else {
            throw LumiError.gitFailed(
                operation: "add",
                detail: (await runGit(["add", "--"] + files, in: repoPath))?.stderr ?? "timeout"
            )
        }
        guard let commitOutput = await runGit(
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

    public func readFile(repoPath: String, file: String) async throws -> String {
        let absolute = try resolveInsideRepo(repoPath, file)
        guard let data = FileManager.default.contents(atPath: absolute) else {
            throw LumiError.fileOperationFailed(path: file, detail: "file could not be read")
        }
        return String(decoding: data, as: UTF8.self)
    }

    public func fileDiff(repoPath: String, file: String) async throws -> UnifiedDiff {
        _ = try resolveInsideRepo(repoPath, file)

        let tracked = await runGit(["ls-files", "--", file], in: repoPath)
        let isTracked = (tracked?.exitCode == 0) && !(tracked?.stdout.isEmpty ?? true)

        if isTracked {
            guard let output = await runGit(["diff", "HEAD", "--", file], in: repoPath),
                  output.exitCode == 0 else {
                throw LumiError.gitFailed(operation: "diff", detail: "git diff failed for \(file)")
            }
            return UnifiedDiffParser.parse(output.stdout, filePath: file)
        }

        // Untracked: /dev/null'a karşı tamamı-ekleme diff'i (exit 1 = fark var, hata değil)
        guard let output = await runGit(
            ["diff", "--no-index", "--", "/dev/null", file],
            in: repoPath
        ) else {
            throw LumiError.gitFailed(operation: "diff", detail: "timeout")
        }
        return UnifiedDiffParser.parse(output.stdout, filePath: file)
    }

    public func commitFiles(repoPath: String, sha: String) async -> [CommitFile] {
        guard let output = await runGit(
            ["diff-tree", "--no-commit-id", "-r", "--name-status", "--root", sha],
            in: repoPath
        ), output.exitCode == 0 else {
            logQuietFailure("commitFiles", nil)
            return []
        }
        return output.stdout.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 2, let statusChar = parts[0].first else { return nil }
            // Skorlu statüler normalize edilir (R100 → renamed — spec/12 temizlik fırsatı)
            let status: FileChangeStatus
            switch statusChar {
            case "A": status = .added
            case "D": status = .deleted
            case "R", "C": status = .renamed
            default: status = .modified
            }
            // Rename'de son path (to) alınır
            let path = String(parts[parts.count - 1])
            return CommitFile(path: path, status: status)
        }
    }

    public func commitFileDiff(repoPath: String, sha: String, file: String) async throws -> UnifiedDiff {
        _ = try resolveInsideRepo(repoPath, file)
        // `git show` ilk (root) commit'te de çalışır — `sha^` parent sorunu yok
        guard let output = await runGit(
            ["show", "--pretty=format:", "--patch", sha, "--", file],
            in: repoPath
        ), output.exitCode == 0 else {
            throw LumiError.gitFailed(operation: "show", detail: "diff unavailable for \(file) @ \(sha)")
        }
        return UnifiedDiffParser.parse(output.stdout, filePath: file)
    }

    // MARK: - Path traversal guard (karar 11: TÜM path'lerde)

    func resolveInsideRepo(_ repoPath: String, _ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: repoPath).standardizedFileURL.path
        let resolved = URL(fileURLWithPath: relativePath, relativeTo: URL(fileURLWithPath: root))
            .standardizedFileURL.path
        guard resolved == root || resolved.hasPrefix(root + "/") else {
            throw LumiError.pathOutsideRepo(path: relativePath)
        }
        return resolved
    }
}
