import Foundation
import LumiKit

struct ExplorerContentSearcher {
    static func search(repoPath: String, paths: [String], query: String) async throws -> ExplorerContentResult {
        guard !query.isEmpty else { return ExplorerContentResult() }
        var matches: [ExplorerContentMatch] = []
        var remainingBytes = 32 * 1024 * 1024
        var limited = paths.count > 10_000
        let guardPath = RepoPathGuard()
        for path in paths.prefix(10_000) {
            try Task.checkCancellation()
            guard let resolved = try? guardPath.resolve(repoPath: repoPath, relativePath: path),
                  let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: resolved)) else { continue }
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: 0)
            guard size <= 2 * 1024 * 1024 else { limited = true; continue }
            guard let data = try? handle.read(upToCount: min(2 * 1024 * 1024, remainingBytes)) else { continue }
            remainingBytes -= data.count
            if !data.contains(0), let text = String(data: data, encoding: .utf8) {
                for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    if line.localizedCaseInsensitiveContains(query) {
                        matches.append(ExplorerContentMatch(path: path, line: index + 1, text: String(line.prefix(500))))
                        if matches.count == 500 { return ExplorerContentResult(matches: matches, isLimited: true) }
                    }
                }
            }
            if remainingBytes == 0 { limited = true; break }
        }
        return ExplorerContentResult(matches: matches, isLimited: limited)
    }
}
