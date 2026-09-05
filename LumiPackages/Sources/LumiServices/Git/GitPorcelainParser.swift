import Foundation
import LumiKit

/// `git` porcelain çıktılarının SAF parse'ı (refactor 3.10): I/O yok, state yok
/// — tamamı birim test edilebilir.
public enum GitPorcelainParser {
    // MARK: - branch --list --no-color

    public static func parseBranches(_ raw: String) -> [GitBranch] {
        raw.split(separator: "\n").compactMap { line in
            guard line.count > 2 else { return nil }
            let isCurrent = line.hasPrefix("* ")
            let name = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.hasPrefix("(") else { return nil } // detached HEAD satırı
            return GitBranch(name: name, isCurrent: isCurrent)
        }
    }

    // MARK: - for-each-ref → default branch

    public static func defaultBranch(from names: Set<String>) -> String? {
        if names.contains("main") { return "main" }
        if names.contains("master") { return "master" }
        return nil
    }

    public static func defaultBranch(fromRefOutput raw: String) -> String? {
        let names = Set(raw.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        return defaultBranch(from: names)
    }

    // MARK: - log --pretty=format:%H<US>%h<US>%an<US>%aI<US>%s

    public static func parseCommits(_ raw: String) -> [GitCommit] {
        let dateParser = ISO8601DateFormatter()
        return raw.split(separator: "\n").compactMap { line in
            let parts = line.split(
                separator: "\u{1f}", maxSplits: 4, omittingEmptySubsequences: false
            )
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

    // MARK: - status --porcelain

    public static func parseStatus(_ raw: String) -> [GitFileChange] {
        raw.split(separator: "\n").compactMap { parseStatusLine(String($0)) }
    }

    /// NUL framing preserves Unicode, newlines, quotes and literal " -> " in paths.
    public static func parseStatusZeroTerminated(_ raw: String) -> [GitFileChange] {
        let entries = raw.split(separator: "\0", omittingEmptySubsequences: false)
        var index = 0
        var result: [GitFileChange] = []
        while index < entries.count {
            let entry = entries[index]
            index += 1
            guard entry.count >= 4 else { continue }
            let codes = Array(entry.prefix(2))
            let path = String(entry.dropFirst(3))
            let status: FileChangeStatus
            if codes.contains("?") { status = .untracked }
            else if codes.contains("R") || codes.contains("C") { status = .renamed }
            else if codes.contains("D") { status = .deleted }
            else if codes.contains("A") { status = .added }
            else { status = .modified }
            result.append(GitFileChange(path: path, status: status))
            if codes.contains("R") || codes.contains("C") { index += 1 }
        }
        return result
    }

    /// Porcelain v1 satırı → sadeleştirilmiş statü: index+worktree
    /// kodları tek statüye iner; rename'de `to` path'i alınır.
    public static func parseStatusLine(_ line: String) -> GitFileChange? {
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

    // MARK: - diff-tree --name-status

    public static func parseDiffTree(_ raw: String) -> [CommitFile] {
        raw.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 2, let statusChar = parts[0].first else { return nil }
            // Skorlu statüler normalize edilir (R100 → renamed)
            let status: FileChangeStatus
            switch statusChar {
            case "A": status = .added
            case "D": status = .deleted
            case "R", "C": status = .renamed
            default: status = .modified
            }
            // Rename'de son path (to) alınır
            return CommitFile(path: String(parts[parts.count - 1]), status: status)
        }
    }
}
