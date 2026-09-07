import Foundation

/// Plastic changeset'lerini `CommitGraph`in beklediği `GitCommit` biçimine
/// çevirir (karar 45 eki) — lane/renk hesabı ve `CommitGraphLaneCanvas`
/// aynen yeniden kullanılır; ikinci bir graph algoritması yazılmaz.
///
/// - `hash` = changeset id'si (metin), `parentHashes` = tek parent (Plastic
///   `{parent}` alanı; merge kaynakları ayrı bir öznitelik olduğundan
///   graph'ta ikinci parent çizilmez).
/// - Sıra changeset id'sine göre yeniden eskiye: Plastic id'leri repo
///   içinde monoton arttığı için bu geçerli bir topolojik sıradır
///   (`git log --topo-order` karşılığı). Pencere dışındaki parent'ın lane'i
///   açık kalır — git'in kesilmiş log'undaki davranışla aynı.
/// - Her branch'in penceredeki EN YENİ changeset'i o branch'in ref rozetini
///   alır; çalışma alanının branch'i `isCurrent` → palet 0 (accent lane).
public enum PlasticHistoryGraph {
    public static func commits(from changesets: [PlasticChangeset], currentBranch: String?) -> [GitCommit] {
        let ordered = changesets.sorted { $0.changesetID > $1.changesetID }
        var seenBranches: Set<String> = []
        return ordered.map { changeset in
            let isBranchTip = seenBranches.insert(changeset.branch).inserted
            let references = isBranchTip
                ? [GitRef(name: changeset.branch, kind: .localBranch, isCurrent: changeset.branch == currentBranch)]
                : []
            return GitCommit(
                hash: hash(changeset.changesetID),
                shortHash: "cs:\(changeset.changesetID)",
                message: changeset.comment,
                author: changeset.owner,
                date: changeset.date,
                parentHashes: changeset.parentID.map { [hash($0)] } ?? [],
                references: references
            )
        }
    }

    /// Çalışma alanının durduğu changeset penceredeyse graph'ın HEAD işareti.
    public static func headHash(workspaceChangesetID: Int?, in changesets: [PlasticChangeset]) -> String? {
        guard let id = workspaceChangesetID, changesets.contains(where: { $0.changesetID == id }) else { return nil }
        return hash(id)
    }

    public static func hash(_ changesetID: Int) -> String { String(changesetID) }
}
