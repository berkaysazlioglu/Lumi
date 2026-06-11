import Foundation
import LumiKit

/// `git diff` / `git show --patch` çıktısını tipli UnifiedDiff modeline çevirir
/// (design/02 §4, karar 4). Saf — testler doğrudan string'le sürer.
enum UnifiedDiffParser {
    static func parse(_ raw: String, filePath: String) -> UnifiedDiff {
        if raw.contains("Binary files ") || raw.contains("GIT binary patch") {
            return UnifiedDiff(filePath: filePath, isBinary: true, hunks: [])
        }

        var hunks: [DiffHunk] = []
        var currentHeader: String?
        var currentLines: [DiffLine] = []
        var oldLineNumber = 0
        var newLineNumber = 0

        func closeHunk() {
            if let header = currentHeader {
                hunks.append(DiffHunk(header: header, lines: currentLines))
            }
            currentHeader = nil
            currentLines = []
        }

        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("@@") {
                closeHunk()
                guard let start = parseHunkHeader(line) else { continue }
                currentHeader = line
                oldLineNumber = start.old
                newLineNumber = start.new
                continue
            }
            guard currentHeader != nil else { continue } // diff/index/---/+++ başlıkları
            if line.hasPrefix("diff ") {
                closeHunk() // aynı çıktıda yeni dosya başlıyor
                continue
            }
            guard let first = line.first else { continue }
            switch first {
            case " ":
                currentLines.append(DiffLine(
                    kind: .context,
                    oldLineNumber: oldLineNumber,
                    newLineNumber: newLineNumber,
                    text: String(line.dropFirst())
                ))
                oldLineNumber += 1
                newLineNumber += 1
            case "-":
                currentLines.append(DiffLine(
                    kind: .deletion,
                    oldLineNumber: oldLineNumber,
                    newLineNumber: nil,
                    text: String(line.dropFirst())
                ))
                oldLineNumber += 1
            case "+":
                currentLines.append(DiffLine(
                    kind: .addition,
                    oldLineNumber: nil,
                    newLineNumber: newLineNumber,
                    text: String(line.dropFirst())
                ))
                newLineNumber += 1
            case "\\":
                continue // "\ No newline at end of file"
            default:
                continue
            }
        }
        closeHunk()
        return UnifiedDiff(filePath: filePath, isBinary: false, hunks: hunks)
    }

    /// `@@ -12,5 +14,6 @@ bağlam` → başlangıç satır numaraları.
    static func parseHunkHeader(_ header: String) -> (old: Int, new: Int)? {
        guard let match = header.range(
            of: #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#,
            options: .regularExpression
        ) else { return nil }
        let segment = header[match]
        let numbers = segment.split(whereSeparator: { !$0.isNumber })
            .prefix(4)
            .compactMap { Int($0) }
        guard numbers.count >= 2 else { return nil }
        // Format: -old[,count] +new[,count] → ilk sayı old, count varsa atla
        let parts = segment.split(separator: " ")
        guard parts.count >= 3 else { return nil }
        let oldPart = parts[1].dropFirst() // "-12,5" → "12,5"
        let newPart = parts[2].dropFirst() // "+14,6" → "14,6"
        let old = Int(oldPart.split(separator: ",")[0]) ?? 0
        let new = Int(newPart.split(separator: ",")[0]) ?? 0
        return (old, new)
    }
}
