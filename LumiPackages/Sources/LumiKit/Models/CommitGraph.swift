import Foundation

/// Bir satırdaki tek dikey "yüzme şeridi": o noktada BEKLENEN parent commit.
public struct CommitGraphLane: Sendable, Equatable {
    /// Bu lane'in aşağıda buluşacağı commit hash'i.
    public let targetHash: String
    /// Palet indeksi (renk seçimi LumiUI'da; model renk bilmez).
    public let colorIndex: Int

    public init(targetHash: String, colorIndex: Int) {
        self.targetHash = targetHash
        self.colorIndex = colorIndex
    }
}

/// Tek commit satırının çizim modeli.
///
/// `inputLanes` satırın ÜST kenarındaki, `outputLanes` ALT kenarındaki lane
/// dizilimidir; komşu satırların input'u önceki satırın output'una eşittir, bu
/// yüzden çizgiler satırlar arasında kesintisiz akar.
public struct CommitGraphRow: Sendable, Equatable, Identifiable {
    public var id: String { commit.hash }
    public let commit: GitCommit
    /// Düğümün oturduğu lane (0 tabanlı).
    public let laneIndex: Int
    public let inputLanes: [CommitGraphLane]
    public let outputLanes: [CommitGraphLane]
    public let isHead: Bool
    public let isMerge: Bool
    /// Merge commit'in İKİNCİ parent'ının çıkış lane'i (yoksa nil).
    public let mergeParentLaneIndex: Int?

    public init(
        commit: GitCommit,
        laneIndex: Int,
        inputLanes: [CommitGraphLane],
        outputLanes: [CommitGraphLane],
        isHead: Bool,
        isMerge: Bool,
        mergeParentLaneIndex: Int?
    ) {
        self.commit = commit
        self.laneIndex = laneIndex
        self.inputLanes = inputLanes
        self.outputLanes = outputLanes
        self.isHead = isHead
        self.isMerge = isMerge
        self.mergeParentLaneIndex = mergeParentLaneIndex
    }

    /// Düğümün rengi: önce kendi çıkış lane'i, yoksa giriş lane'i, yoksa 0.
    public var nodeColorIndex: Int {
        if laneIndex < outputLanes.count { return outputLanes[laneIndex].colorIndex }
        if laneIndex < inputLanes.count { return inputLanes[laneIndex].colorIndex }
        return 0
    }

    /// Satırın kapladığı lane sayısı (kolon genişliği hesabı).
    public var laneCount: Int { max(inputLanes.count, outputLanes.count, 1) }
}

/// `git log --topo-order` çıktısını lane'li bir çizim modeline çeviren SAF
/// algoritma (Orca `buildGitHistoryViewModels` portu, karar 40).
///
/// Kural: her satırda, giriş lane'lerinden bu commit'i hedefleyen İLK lane
/// kapanır ve yerine commit'in ilk parent'ı yazılır; aynı commit'i hedefleyen
/// diğer lane'ler düşer (dallar birleşir); kalan lane'ler sırasını korur; ilk
/// parent dışındaki parent'lar sona yeni lane açar.
///
/// Orca'dan tek bilinçli sapma: parent'sız (root) commit orada TÜM lane'leri
/// düşürür — burada yalnız kendi lane'i kapanır, yandaki bağımsız tepe ayakta
/// kalır (`testRootCommitKeepsOtherLanesOpen`).
public enum CommitGraph {
    /// Renk paleti basamak sayısı (LumiUI'daki `Theme.Graph.laneColors` ile aynı).
    public static let paletteSize = 5

    public static func build(_ commits: [GitCommit], headHash: String?) -> [CommitGraphRow] {
        var rows: [CommitGraphRow] = []
        rows.reserveCapacity(commits.count)
        var rotation = -1

        func nextRotatingColor() -> Int {
            rotation += 1
            return currentBranchColor + 1 + rotation % (paletteSize - 1)
        }

        for commit in commits {
            let inputLanes = rows.last?.outputLanes ?? []
            let currentColor = isOnCurrentBranch(commit) ? currentBranchColor : nil
            var outputLanes: [CommitGraphLane] = []
            var firstParentAdded = false

            for lane in inputLanes where lane.targetHash != commit.hash {
                outputLanes.append(lane)
            }
            // İlk parent, kapanan lane'in TAM YERİNE geçer (dallar sola kaymaz).
            // `firstIndex` olduğu için ondan önceki hiçbir lane bu commit'i
            // hedeflemez; ekleme noktası doğrudan o indekstir.
            if let firstParent = commit.parentHashes.first,
               let closedIndex = inputLanes.firstIndex(where: { $0.targetHash == commit.hash }) {
                outputLanes.insert(
                    CommitGraphLane(
                        targetHash: firstParent,
                        colorIndex: currentColor ?? inputLanes[closedIndex].colorIndex
                    ),
                    at: closedIndex
                )
                firstParentAdded = true
            }

            for index in (firstParentAdded ? 1 : 0) ..< commit.parentHashes.count {
                let color = (index == 0 ? currentColor : nil) ?? nextRotatingColor()
                outputLanes.append(
                    CommitGraphLane(targetHash: commit.parentHashes[index], colorIndex: color)
                )
            }

            let laneIndex = inputLanes.firstIndex { $0.targetHash == commit.hash }
                ?? inputLanes.count
            let mergeParentLaneIndex = commit.parentHashes.count > 1
                ? outputLanes.lastIndex { $0.targetHash == commit.parentHashes[1] }
                : nil

            rows.append(CommitGraphRow(
                commit: commit,
                laneIndex: laneIndex,
                inputLanes: inputLanes,
                outputLanes: outputLanes,
                isHead: headHash != nil && commit.hash == headHash,
                isMerge: commit.isMerge,
                mergeParentLaneIndex: mergeParentLaneIndex
            ))
        }

        return rows
    }

    /// Tüm satırların ortak kolon genişliği — metinlerin hizalı kalması için
    /// grafik kolonu satır başına DEĞİL, liste başına ölçülür.
    public static func maxLaneCount(_ rows: [CommitGraphRow]) -> Int {
        max(rows.map(\.laneCount).max() ?? 1, 1)
    }

    /// Checkout edilmiş branch'e ayrılan sabit palet basamağı (Orca'daki
    /// `GIT_HISTORY_REF_COLOR` karşılığı). Round-robin bu basamağı ATLAR, aksi
    /// halde yan dallar HEAD lane'iyle aynı rengi alabiliyordu.
    public static let currentBranchColor = 0

    private static func isOnCurrentBranch(_ commit: GitCommit) -> Bool {
        commit.references.contains { $0.isCurrent || $0.kind == .head }
    }
}
