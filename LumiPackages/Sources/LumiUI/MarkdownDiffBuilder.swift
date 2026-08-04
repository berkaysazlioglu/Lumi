import Foundation
import LumiKit

/// Markdown dosyalarını "render'lı" göstermek için saf dönüşüm (karar 21):
/// `UnifiedDiff` (veya tam dosya metni) → blok stili çözülmüş satır modeli.
///
/// Düzen bilinçli olarak **tek kolon (unified)**: iki kolona sıkıştırılmış
/// render'lı markdown okunmuyor (satır sarmalı + başlık ölçekleri hizayı bozuyor).
/// Ham side-by-side görünüm `SideBySideDiffView` ile bir tuşla erişilebilir kalır.
enum MarkdownDiffBuilder {
    struct Model: Equatable {
        let rows: [Row]
        let isBinary: Bool
    }

    enum Row: Equatable {
        case hunk(String)
        case line(Line)
    }

    struct Line: Equatable {
        let kind: DiffLine.Kind
        let oldLineNumber: Int?
        let newLineNumber: Int?
        let style: BlockStyle
        /// Blok işaretleri (`## `, `- `, `> `) ayrıştırılmış içerik; satır-içi
        /// markdown (kalın/italik/kod/link) render aşamasında çözülür.
        let content: String
    }

    /// Satırın markdown blok rolü. Girinti seviyeleri 2 boşluk = 1 kademe.
    enum BlockStyle: Equatable {
        case heading(level: Int)
        case bullet(indent: Int)
        case ordered(indent: Int, marker: String)
        case quote
        /// Fence içindeki kod satırı (içerik olduğu gibi korunur).
        case code
        /// Fence'in kendisi (``` / ~~~) — dil etiketi taşır.
        case fence
        case rule
        case table
        case paragraph
        case blank
    }

    static let maxIndentLevel = 4

    // MARK: - Girişler

    /// diff / commit-diff modu. Fence durumu HUNK BAŞINA sıfırlanır: hunk'lar
    /// süreksizdir, dosyanın tamamındaki fence durumu bilinemez.
    static func build(_ diff: UnifiedDiff) -> Model {
        if diff.isBinary { return Model(rows: [], isBinary: true) }

        var rows: [Row] = []
        for hunk in diff.hunks {
            rows.append(.hunk(hunk.header))
            var isInsideFence = false
            for line in hunk.lines {
                let parsed = parse(line.text, insideFence: isInsideFence)
                if parsed.style == .fence { isInsideFence.toggle() }
                rows.append(.line(Line(
                    kind: line.kind,
                    oldLineNumber: line.oldLineNumber,
                    newLineNumber: line.newLineNumber,
                    style: parsed.style,
                    content: parsed.content
                )))
            }
        }
        return Model(rows: rows, isBinary: false)
    }

    /// view modu: tam dosya metni → aynı satır modeli (tüm satırlar context).
    static func buildDocument(_ text: String) -> Model {
        var rows: [Row] = []
        var isInsideFence = false
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, rawLine) in lines.enumerated() {
            let parsed = parse(String(rawLine), insideFence: isInsideFence)
            if parsed.style == .fence { isInsideFence.toggle() }
            rows.append(.line(Line(
                kind: .context,
                oldLineNumber: nil,
                newLineNumber: index + 1,
                style: parsed.style,
                content: parsed.content
            )))
        }
        return Model(rows: rows, isBinary: false)
    }

    // MARK: - Blok ayrıştırma

    static func parse(_ text: String, insideFence: Bool) -> (style: BlockStyle, content: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { return (.fence, trimmed) }
        if insideFence { return (.code, text) }
        if trimmed.isEmpty { return (.blank, "") }
        if let heading = heading(trimmed) { return (.heading(level: heading.level), heading.content) }
        if trimmed.hasPrefix(">") {
            return (.quote, String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
        }
        if isRule(trimmed) { return (.rule, "") }
        if trimmed.hasPrefix("|") { return (.table, trimmed) }

        let indent = indentLevel(text)
        if let bullet = bullet(trimmed) { return (.bullet(indent: indent), bullet) }
        if let ordered = ordered(trimmed) {
            return (.ordered(indent: indent, marker: ordered.marker), ordered.content)
        }
        return (.paragraph, trimmed)
    }

    /// `## Başlık` → (2, "Başlık"). `#tag` (boşluksuz) başlık DEĞİLDİR.
    private static func heading(_ trimmed: String) -> (level: Int, content: String)? {
        guard trimmed.hasPrefix("#") else { return nil }
        let hashes = trimmed.prefix { $0 == "#" }
        guard hashes.count <= 6 else { return nil }
        let rest = trimmed.dropFirst(hashes.count)
        guard rest.isEmpty || rest.hasPrefix(" ") else { return nil }
        return (hashes.count, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let stripped = trimmed.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        for marker: Character in ["-", "*", "_"] where stripped.allSatisfy({ $0 == marker }) {
            return true
        }
        return false
    }

    private static func bullet(_ trimmed: String) -> String? {
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            return String(trimmed.dropFirst(marker.count))
        }
        return nil
    }

    /// `12. içerik` / `12) içerik` → ("12.", "içerik").
    private static func ordered(_ trimmed: String) -> (marker: String, content: String)? {
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = trimmed.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return ("\(digits).", String(rest.dropFirst(2)))
    }

    private static func indentLevel(_ text: String) -> Int {
        var columns = 0
        for character in text {
            if character == " " {
                columns += 1
            } else if character == "\t" {
                columns += 2
            } else {
                break
            }
        }
        return min(columns / 2, maxIndentLevel)
    }

    // MARK: - Satır-içi markdown

    /// Kalın/italik/kod/link/üstü-çizili → `AttributedString` (inline-only:
    /// blok işaretleri zaten ayrıldı). Parse hatasında düz metne düşülür.
    static func inlineAttributed(_ text: String) -> AttributedString {
        guard !text.isEmpty else { return AttributedString("") }
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
