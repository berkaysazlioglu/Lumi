import Foundation
import LumiKit

/// Side-by-side diff görünüm modeli + saf dönüşüm (karar 4 revize: unified →
/// side-by-side). UnifiedDiff'i sol (eski) / sağ (yeni) hücre satırlarına çevirir;
/// SwiftUI'dan bağımsız test edilir.
enum SideBySideDiffBuilder {
    struct Model: Equatable {
        let rows: [Row]
        let isBinary: Bool
    }

    enum Row: Equatable {
        case header(String)                  // @@ hunk başlığı (tam genişlik)
        case lines(left: Cell?, right: Cell?) // nil hücre = karşılıksız (filler)
    }

    struct Cell: Equatable {
        let lineNumber: Int?
        let text: String
        let kind: DiffLine.Kind
    }

    /// Hunk içinde ardışık silme/eklemeler hizalanır: del[i] ↔ add[i] aynı satıra
    /// (değiştirilen satır → solda eski, sağda yeni); fazlalar karşılıksız (filler).
    /// Context satırı iki tarafta da görünür (sol oldLine, sağ newLine).
    static func build(_ diff: UnifiedDiff) -> Model {
        if diff.isBinary { return Model(rows: [], isBinary: true) }

        var rows: [Row] = []
        for hunk in diff.hunks {
            rows.append(.header(hunk.header))
            var deletions: [DiffLine] = []
            var additions: [DiffLine] = []

            func flushPairs() {
                let pairCount = max(deletions.count, additions.count)
                for index in 0..<pairCount {
                    let left = index < deletions.count
                        ? Cell(lineNumber: deletions[index].oldLineNumber,
                               text: deletions[index].text, kind: .deletion)
                        : nil
                    let right = index < additions.count
                        ? Cell(lineNumber: additions[index].newLineNumber,
                               text: additions[index].text, kind: .addition)
                        : nil
                    rows.append(.lines(left: left, right: right))
                }
                deletions.removeAll(keepingCapacity: true)
                additions.removeAll(keepingCapacity: true)
            }

            for line in hunk.lines {
                switch line.kind {
                case .deletion:
                    deletions.append(line)
                case .addition:
                    additions.append(line)
                case .context:
                    flushPairs()
                    rows.append(.lines(
                        left: Cell(lineNumber: line.oldLineNumber, text: line.text, kind: .context),
                        right: Cell(lineNumber: line.newLineNumber, text: line.text, kind: .context)
                    ))
                }
            }
            flushPairs()
        }
        return Model(rows: rows, isBinary: false)
    }
}
