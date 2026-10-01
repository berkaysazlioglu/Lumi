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
    /// Gerçek commit mi, yoksa upstream karşılaştırmasının sentetik sınır
    /// satırı mı (Orca `incoming-changes` / `outgoing-changes`).
    public enum Kind: Sendable, Equatable {
        case commit
        /// Upstream'de olup HEAD'de olmayan commit'lerin tek temsilcisi.
        case incomingChanges
        /// HEAD'de olup upstream'e push edilmemiş commit'lerin başlığı.
        case outgoingChanges
    }

    public var id: String { commit.hash }
    public let kind: Kind
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
        mergeParentLaneIndex: Int?,
        kind: Kind = .commit
    ) {
        self.kind = kind
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

    public var isBoundary: Bool { kind != .commit }

    /// Aynı commit, yeni lane dizilimi: düğüm ve merge-parent indeksleri
    /// lane'lerden YENİDEN türetilir (sınır satırı eklemesi komşuları kaydırır).
    func relaned(input: [CommitGraphLane], output: [CommitGraphLane]) -> CommitGraphRow {
        CommitGraphRow.make(commit: commit, input: input, output: output, isHead: isHead, kind: kind)
    }

    static func make(
        commit: GitCommit,
        input: [CommitGraphLane],
        output: [CommitGraphLane],
        isHead: Bool,
        kind: Kind
    ) -> CommitGraphRow {
        CommitGraphRow(
            commit: commit,
            laneIndex: input.firstIndex { $0.targetHash == commit.hash } ?? input.count,
            inputLanes: input,
            outputLanes: output,
            isHead: isHead,
            isMerge: commit.isMerge,
            mergeParentLaneIndex: commit.parentHashes.count > 1
                ? output.lastIndex { $0.targetHash == commit.parentHashes[1] }
                : nil,
            kind: kind
        )
    }
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
///
/// Etiket renkleri (Orca `colorMap`): checkout edilmiş branch'i taşıyan commit
/// ilk-parent lane'ine `currentBranchColor`, `upstream` verilmişse o uzak
/// branch'i taşıyan commit `remoteRefColor` verir. `upstream` yalnız Git
/// history'sinde geçilir; Plastic graph'ı onsuz kurulur ve davranışı değişmez.
public enum CommitGraph {
    /// Renk paleti basamak sayısı (LumiUI'daki `Theme.Graph.laneColors` ile aynı).
    public static let paletteSize = 5
    /// Upstream (ör. `origin/main`) lane'ine ve rozetine ayrılan renk — dönen
    /// paletin DIŞINDADIR (Orca `git-graph-remote-ref`).
    public static let remoteRefColor = paletteSize

    /// Sentetik sınır satırlarının commit kimlikleri (Orca ile aynı).
    public static let incomingChangesID = "git-history-incoming-changes"
    public static let outgoingChangesID = "git-history-outgoing-changes"

    public static func build(
        _ commits: [GitCommit],
        headHash: String?,
        upstream: String? = nil
    ) -> [CommitGraphRow] {
        var rows: [CommitGraphRow] = []
        rows.reserveCapacity(commits.count)
        var rotation = -1
        // Yan-parent etiket araması yalnız upstream varken gerekir; doğrusal
        // history'ler sözlük maliyeti ödemesin diye tembel kurulur (Orca).
        var commitsByHash: [String: GitCommit]?

        func nextRotatingColor() -> Int {
            rotation += 1
            return currentBranchColor + 1 + rotation % (paletteSize - 1)
        }

        func sideParentColor(_ parentHash: String) -> Int? {
            guard upstream != nil else { return nil }
            if commitsByHash == nil {
                commitsByHash = Dictionary(commits.map { ($0.hash, $0) }, uniquingKeysWith: { first, _ in first })
            }
            return commitsByHash?[parentHash].flatMap { carriesUpstream($0, upstream) ? remoteRefColor : nil }
        }

        for commit in commits {
            let inputLanes = rows.last?.outputLanes ?? []
            let commitLabel = labelColor(commit, upstream: upstream)
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
                        colorIndex: commitLabel ?? inputLanes[closedIndex].colorIndex
                    ),
                    at: closedIndex
                )
                firstParentAdded = true
            }

            for index in (firstParentAdded ? 1 : 0) ..< commit.parentHashes.count {
                let label = index == 0 ? commitLabel : sideParentColor(commit.parentHashes[index])
                let color = label ?? nextRotatingColor()
                outputLanes.append(
                    CommitGraphLane(targetHash: commit.parentHashes[index], colorIndex: color)
                )
            }

            rows.append(CommitGraphRow.make(
                commit: commit,
                input: inputLanes,
                output: outputLanes,
                isHead: headHash != nil && commit.hash == headHash,
                kind: .commit
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

    /// Rozet rengi (Orca `colorMap`): yalnız checkout edilmiş ref ve upstream
    /// renk alır; diğer branch/tag rozetleri nötrdür (nil).
    public static func refColorIndex(_ ref: GitRef, upstream: String?) -> Int? {
        if ref.isCurrent || ref.kind == .head { return currentBranchColor }
        if ref.kind == .remoteBranch, ref.name == upstream { return remoteRefColor }
        return nil
    }

    private static func labelColor(_ commit: GitCommit, upstream: String?) -> Int? {
        if isOnCurrentBranch(commit) { return currentBranchColor }
        return carriesUpstream(commit, upstream) ? remoteRefColor : nil
    }

    private static func isOnCurrentBranch(_ commit: GitCommit) -> Bool {
        commit.references.contains { $0.isCurrent || $0.kind == .head }
    }

    private static func carriesUpstream(_ commit: GitCommit, _ upstream: String?) -> Bool {
        guard let upstream else { return false }
        return commit.references.contains { $0.kind == .remoteBranch && $0.name == upstream }
    }
}
