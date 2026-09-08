import Foundation
import LumiKit

/// `cm` CLI çıktılarının saf parse'ı (I/O yok) — karar 46.
///
/// Girdi biçimleri gerçek `cm 11.0` çıktısından alınmıştır:
/// - header: `STATUS|2105|sand_out|uncosoft@cloud`
/// - selector: `smartbranch "/main" changeset "2105"` (veya `branch "/main"`)
/// - status: `CH|/abs/path/File.cs|False|NO_MERGES`
/// - changesets: `2197<US>/main<US>owner<US>2026-07-07T11:24:09+03:00<US>2191<US>comment`
///   (US = ASCII 0x1F unit separator; `{tab}` token'ı `cm find`de geçersizdir ve
///   yorum içinde sekme/`|` geçebilir — ham kontrol karakteri argv'den aynen geçer)
public enum PlasticOutputParser {
    public static let fieldSeparator: Character = "|"
    public static let changesetFieldSeparator: Character = "\u{1F}"

    // MARK: - Header / selector

    /// `cm status --header --machinereadable --fieldseparator=|` → changeset,
    /// repo, server. Branch ayrı komuttan gelir (`parseSelectorBranch`).
    public static func parseHeader(_ stdout: String) -> (changesetID: Int, repository: String, server: String)? {
        guard let line = stdout.split(whereSeparator: \.isNewline).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return nil
        }
        let fields = line.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 4, fields[0] == "STATUS", let changeset = Int(fields[1]) else { return nil }
        return (changeset, fields[2], fields[3])
    }

    /// `cm showselector` → `smartbranch "/main"` ya da `branch "/main"`.
    public static func parseSelectorBranch(_ stdout: String) -> String? {
        let pattern = #"(?:smartbranch|branch)\s+"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: stdout, range: NSRange(stdout.startIndex..., in: stdout)),
              let range = Range(match.range(at: 1), in: stdout) else { return nil }
        return String(stdout[range])
    }

    // MARK: - Status

    /// `cm status --short --machinereadable --fieldseparator=| --all` satırları.
    /// Mutlak path'ler çalışma alanı köküne göre relative'e çevrilir; kök
    /// dışındaki ve tanınmayan kodlu satırlar atlanır. Ignored (IG) hiç
    /// listelenmez.
    public static func parseStatus(_ stdout: String, workspacePath: String) -> [PlasticFileChange] {
        let root = normalizedRoot(workspacePath)
        return stdout.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 2, let status = status(forCode: fields[0]) else { return nil }
            // Taşımada yeni path ikinci bir mutlak alan olarak gelebilir; kök
            // altındaki SON mutlak alan gösterilecek path'tir.
            let absolute = fields.dropFirst().last { $0.hasPrefix(root) } ?? fields[1]
            guard let relative = relativePath(absolute, root: root), !relative.isEmpty else { return nil }
            return PlasticFileChange(path: relative, status: status)
        }
    }

    /// Plastic durum kodu → ortak `FileChangeStatus`. Bileşik kodlarda
    /// (`CO+MV`, `CO+RP`, `CO+CH`) en anlamlı parça kazanır: taşıma/silme/
    /// ekleme, checkout'un (CO) önündedir — gerçek çalışma alanında
    /// `CO+MV` "Moved items" grubuna düşmelidir. RP (replaced) tek başına ya da
    /// CO ile birlikte içerik değişikliği sayılır.
    public static func status(forCode rawCode: String) -> FileChangeStatus? {
        let codes = Set(rawCode.split(separator: "+").map(String.init))
        if !codes.isDisjoint(with: ["MV", "LM"]) { return .renamed }
        if !codes.isDisjoint(with: ["DE", "LD"]) { return .deleted }
        if !codes.isDisjoint(with: ["AD", "CP"]) { return .added }
        if codes.contains("PR") { return .untracked }
        if !codes.isDisjoint(with: ["CH", "CO", "RP"]) { return .modified }
        return nil
    }

    // MARK: - Changesets

    /// `cm find changesets --format='{changesetid}<US>{branch}<US>…<US>{comment}'`
    /// çıktısı. Yorum SON alandır: içindeki sekme/`|` korunur; sayısal id ile
    /// başlamayan satırlar önceki kaydın çok satırlı yorumuna eklenir.
    /// Tarihi çözülemeyen kayıt atlanır.
    public static func parseChangesets(_ stdout: String) -> [PlasticChangeset] {
        var records: [[String]] = []
        for line in stdout.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = line.hasSuffix("\r") ? String(line.dropLast()) : String(line)
            let fields = text.split(separator: changesetFieldSeparator, maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
            if fields.count == 6, Int(fields[0]) != nil {
                records.append(fields)
            } else if !records.isEmpty, !text.isEmpty {
                records[records.count - 1][5] += "\n" + text
            }
        }
        let dates = ISO8601DateFormatter()
        return records.compactMap { fields in
            guard let id = Int(fields[0]), let date = dates.date(from: fields[3]) else { return nil }
            return PlasticChangeset(
                changesetID: id,
                branch: fields[1],
                owner: fields[2],
                date: date,
                comment: fields[5].trimmingCharacters(in: .whitespacesAndNewlines),
                parentID: Int(fields[4])
            )
        }
    }

    // MARK: - Path yardımcıları

    private static func normalizedRoot(_ path: String) -> String {
        var root = path
        while root.count > 1, root.hasSuffix("/") { root.removeLast() }
        return root
    }

    private static func relativePath(_ absolute: String, root: String) -> String? {
        guard absolute.hasPrefix(root) else { return nil }
        var rest = String(absolute.dropFirst(root.count))
        guard rest.isEmpty || rest.hasPrefix("/") else { return nil }
        while rest.hasPrefix("/") { rest.removeFirst() }
        return rest
    }
}
