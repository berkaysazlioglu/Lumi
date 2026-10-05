import Foundation

/// Favori ekleme aramasının bir sonucu (karar 107).
public struct FavoriteFileCandidate: Sendable, Equatable, Identifiable {
    public let path: String
    /// Git'in ignore ettiği ya da Unity `.meta` dosyası — listede sona düşer.
    public let isDeprioritized: Bool

    public init(path: String, isDeprioritized: Bool = false) {
        self.path = path
        self.isDeprioritized = isDeprioritized
    }

    public var id: String { path }
    public var name: String { FavoriteFilePath.name(of: path) }
    public var directory: String { FavoriteFilePath.directory(of: path) }
}

/// Checkout ağacında dosya arama (karar 107) — saf, MainActor dışında koşar.
///
/// Sorgu boşlukla parçalanır; her parça relative yolun HERHANGİ bir yerinde
/// geçmelidir (büyük/küçük harf duyarsız). Böylece yalnız dosya adı değil
/// klasör adı da aranır: `scripts player` → `Assets/Scripts/Player.cs`,
/// `Editor/` → o klasördeki her dosya. Sıra: bütün parçalar dosya adında ve
/// ad ilk parçayla başlıyor → bütün parçalar adda → klasörden eşleşen; ignored
/// ve `.meta` dosyaları aynı sırayla en sona; grup içinde kısa yol önce.
public enum FavoriteFileSearch {
    public static let resultLimit = 200
    /// Öncelikli olmayan dosyalar her eşleşme grubunun ardından gelir.
    private static let deprioritizedOffset = 3

    public static func search(
        _ tree: [FileTreeNode], query: String, limit: Int = resultLimit
    ) -> [FavoriteFileCandidate] {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return [] }
        var ranked: [(rank: Int, candidate: FavoriteFileCandidate)] = []
        forEachFile(in: tree) { node in
            let path = node.path.lowercased()
            guard tokens.allSatisfy({ path.contains($0) }) else { return }
            let name = FavoriteFilePath.name(of: path)
            let tier: Int
            if tokens.allSatisfy({ name.contains($0) }) {
                tier = name.hasPrefix(tokens[0]) ? 0 : 1
            } else {
                tier = 2
            }
            let candidate = FavoriteFileCandidate(path: node.path, isDeprioritized: isDeprioritized(node))
            ranked.append(((candidate.isDeprioritized ? deprioritizedOffset : 0) + tier, candidate))
        }
        return ranked
            .sorted {
                if $0.rank != $1.rank { return $0.rank < $1.rank }
                if $0.candidate.path.count != $1.candidate.path.count {
                    return $0.candidate.path.count < $1.candidate.path.count
                }
                return $0.candidate.path < $1.candidate.path
            }
            .prefix(limit)
            .map(\.candidate)
    }

    /// Ağaçtaki bütün dosyaların relative yolları (yer değiştirme araması için).
    public static func filePaths(in tree: [FileTreeNode]) -> [String] {
        var paths: [String] = []
        forEachFile(in: tree) { paths.append($0.path) }
        return paths
    }

    private static func isDeprioritized(_ node: FileTreeNode) -> Bool {
        node.isIgnored || node.name.hasSuffix(".meta")
    }

    private static func forEachFile(in nodes: [FileTreeNode], _ body: (FileTreeNode) -> Void) {
        for node in nodes {
            switch node.type {
            case .file: body(node)
            case .folder: forEachFile(in: node.children, body)
            }
        }
    }
}
