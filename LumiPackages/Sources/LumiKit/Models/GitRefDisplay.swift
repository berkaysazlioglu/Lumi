import Foundation

/// Git history rozetlerinin sunum kuralları (Orca `dedupeRemoteTrackingRefs` +
/// `compareGitHistoryRefs` portu). Saf; Plastic rozetleri bunu kullanmaz.
public enum GitRefDisplay {
    /// Rozet sırası: checkout edilmiş ref → upstream → kalanlar ayrıştırıcının
    /// kategori sırasında (yerel → uzak → tag).
    public static func badges(_ refs: [GitRef], upstream: String?) -> [GitRef] {
        let visible = dedupeRemoteTracking(refs)
        func rank(_ ref: GitRef) -> Int {
            if ref.isCurrent || ref.kind == .head { return 0 }
            if ref.kind == .remoteBranch, ref.name == upstream { return 1 }
            return 2
        }
        return visible.enumerated()
            .sorted { lhs, rhs in
                let (left, right) = (rank(lhs.element), rank(rhs.element))
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }

    /// Aynı commit'te yerel `feature` varken `origin/feature` rozeti fazlalıktır;
    /// ikisi ayrıştığında farklı commit'lere düşer ve ikisi de görünür.
    ///
    /// Belirsiz adlar korunur: `foo/bar/main` uzak `foo` + dal `bar/main` de
    /// olabilir; aynı dal adına birden çok uzak (`origin/main`, `upstream/main`)
    /// eşleşiyorsa da hangisinin upstream olduğu bilinmediği için ikisi kalır.
    public static func dedupeRemoteTracking(_ refs: [GitRef]) -> [GitRef] {
        let localNames = Set(refs.filter { $0.kind == .localBranch }.map(\.name))
        guard !localNames.isEmpty else { return refs }

        var matchCounts: [String: Int] = [:]
        for ref in refs {
            guard let branch = matchingLocalBranch(ref, localNames: localNames) else { continue }
            matchCounts[branch, default: 0] += 1
        }
        return refs.filter { ref in
            guard let branch = matchingLocalBranch(ref, localNames: localNames) else { return true }
            return matchCounts[branch] != 1
        }
    }

    /// Uzak ref'in kısa adı (`origin/feature`) tek `/` içeriyor ve yerel bir
    /// branch'le eşleşiyorsa o branch'in adı.
    private static func matchingLocalBranch(_ ref: GitRef, localNames: Set<String>) -> String? {
        guard ref.kind == .remoteBranch else { return nil }
        let parts = ref.name.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        let branch = String(parts[1])
        return localNames.contains(branch) ? branch : nil
    }
}
