import Foundation

/// Upstream karşılaştırmasının sentetik sınır satırları (Orca
/// `addIncomingOutgoingChangesHistoryItems` portu).
///
/// History yalnız `HEAD`ten okunduğu için upstream'in çekilmemiş commit'leri
/// listede yoktur; "Incoming Changes" satırı onları merge-base'in hemen
/// üstünde tek bir kesikli düğümle temsil eder ve upstream lane'ini merge-base'e
/// bağlar. "Outgoing Changes" satırı HEAD'in üstüne oturur: push edilmemiş
/// commit'lerin başlığıdır.
public extension CommitGraph {
    static func addBoundaryRows(_ rows: [CommitGraphRow], context: GitHistoryContext?) -> [CommitGraphRow] {
        guard let context, let upstream = context.upstream, let mergeBase = context.mergeBase,
              upstream.hash != context.headHash else { return rows }
        var result = rows
        if context.hasIncomingChanges {
            addIncomingRow(&result, upstream: upstream, mergeBase: mergeBase)
        }
        if context.hasOutgoingChanges {
            addOutgoingRow(&result, headHash: context.headHash, branchName: context.currentBranch)
        }
        return result
    }

    // MARK: - Incoming

    private static func addIncomingRow(
        _ rows: inout [CommitGraphRow],
        upstream: GitHistoryContext.Upstream,
        mergeBase: String
    ) {
        guard let afterIndex = rows.firstIndex(where: { $0.commit.hash == mergeBase }) else { return }
        let beforeIndex = rows.lastIndex { row in
            row.outputLanes.contains { $0.targetHash == mergeBase }
        }
        // "Gelen var mı" kararı yalnız `hasIncomingChanges`'tadır (upstream ≠
        // merge-base ⇒ upstream HEAD'in atası değil). Üstteki satırın merge-base'i
        // parent olarak taşıyan bir merge olması bunu değiştirmez.
        let before = beforeIndex.map { rows[$0] }

        let after = rows[afterIndex]
        // Incoming lane'i EN SAĞA eklenir. Orca onu yerel lane'in hemen yanına
        // sokar; bu, üstteki satırın kendi çıkış lane'lerini kaydırıyor ve o
        // satırın düğümü upstream rengine boyanıp ilk-parent çizgisi boşluktan
        // doğuyordu (bilinçli sapma).
        let incomingLane = CommitGraphLane(targetHash: incomingChangesID, colorIndex: remoteRefColor)
        let input = (before?.outputLanes ?? after.inputLanes) + [incomingLane]
        let output = input.map { lane in
            lane == incomingLane ? CommitGraphLane(targetHash: mergeBase, colorIndex: remoteRefColor) : lane
        }

        if let beforeIndex, let before {
            rows[beforeIndex] = before.relaned(input: before.inputLanes, output: input)
        }

        let incoming = GitCommit(
            hash: incomingChangesID,
            shortHash: "",
            message: "Incoming Changes",
            author: upstream.name,
            date: .distantPast,
            parentHashes: [mergeBase]
        )
        rows.insert(
            CommitGraphRow.make(commit: incoming, input: input, output: output, isHead: false, kind: .incomingChanges),
            at: afterIndex
        )
        rows[afterIndex + 1] = after.relaned(input: output, output: after.outputLanes)
    }

    // MARK: - Outgoing

    private static func addOutgoingRow(_ rows: inout [CommitGraphRow], headHash: String, branchName: String?) {
        guard let headIndex = rows.firstIndex(where: { $0.isHead && $0.commit.hash == headHash }) else { return }
        let head = rows[headIndex]
        let headLane = CommitGraphLane(targetHash: headHash, colorIndex: currentBranchColor)
        let input = head.inputLanes
        let output = input + [headLane]

        let outgoing = GitCommit(
            hash: outgoingChangesID,
            shortHash: "",
            message: "Outgoing Changes",
            author: branchName ?? String(headHash.prefix(7)),
            date: .distantPast,
            parentHashes: [headHash]
        )
        rows.insert(
            CommitGraphRow.make(commit: outgoing, input: input, output: output, isHead: false, kind: .outgoingChanges),
            at: headIndex
        )
        rows[headIndex + 1] = head.relaned(input: output, output: head.outputLanes)
    }
}
