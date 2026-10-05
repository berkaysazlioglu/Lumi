import Foundation

/// Projeye bağlı favori dosya (karar 107).
///
/// Hızlı komutlar gibi (karar 92) PROJE başına tanımlanır ve aktif checkout'ta
/// çözülür: yol proje köküne göre relative'dir, `main` ya da yönetilen bir
/// workspace'te aynı yol açılır. Persistence: `config.json` →
/// `projectFavoriteFiles`.
public struct ProjectFavoriteFile: Sendable, Equatable, Identifiable {
    public let id: String
    public let projectPath: String
    /// '/' ayraçlı, checkout köküne göre yol.
    public var relativePath: String

    public init(id: String = UUID().uuidString, projectPath: String, relativePath: String) {
        self.id = id
        self.projectPath = projectPath
        self.relativePath = relativePath
    }

    public var name: String { FavoriteFilePath.name(of: relativePath) }

    /// Kökteki dosyada boş.
    public var directory: String { FavoriteFilePath.directory(of: relativePath) }

    public var isValid: Bool { FavoriteFilePath.isValidRelative(relativePath) }
}

/// Relative yol yardımcıları — kayıt doğrulaması ve görünüm aynı kuralı okur.
public enum FavoriteFilePath {
    /// Checkout'un dışına çıkamayan relative yol: boş değil, mutlak değil,
    /// `.`/`..`/boş bileşen yok.
    public static func isValidRelative(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }

    public static func name(of path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    public static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    public static func absolute(_ relativePath: String, in checkoutPath: String) -> String {
        checkoutPath.hasSuffix("/") ? checkoutPath + relativePath : checkoutPath + "/" + relativePath
    }
}

/// Favorinin aktif checkout'taki durumu (karar 107).
public enum FavoriteFileLocation: Sendable, Equatable {
    /// Kayıtlı yolda duruyor.
    case present
    /// Kayıtlı yolda yok ama aynı adlı tek bir aday var (taşınmış).
    case moved(to: String)
    /// Silinmiş ya da nereye gittiği belirsiz (aday yok veya birden çok eşit aday).
    case missing
}

/// Menüde çizilen satır: favori + çözülmüş konumu.
public struct FavoriteFileEntry: Sendable, Equatable, Identifiable {
    public let favorite: ProjectFavoriteFile
    public let location: FavoriteFileLocation

    public init(favorite: ProjectFavoriteFile, location: FavoriteFileLocation) {
        self.favorite = favorite
        self.location = location
    }

    public var id: String { favorite.id }

    /// Açılacak relative yol; kayıpsa `nil`.
    public var resolvedPath: String? {
        switch location {
        case .present: favorite.relativePath
        case .moved(let path): path
        case .missing: nil
        }
    }

    public var isMissing: Bool { location == .missing }
}

/// Kayıtlı yolu artık dosya olmayan favorinin yeni yerini bulur (karar 107).
///
/// Ad korunarak taşınan dosyayı yakalar: checkout ağacındaki aynı adlı
/// dosyalar arasından eski yolla en çok dizin bileşenini (baştan + sondan)
/// paylaşan TEK aday seçilir. Eşitlik varsa tahmin yapılmaz — yanlış dosyayı
/// açmak, "bulunamadı" demekten kötüdür. Adı da değişen dosya `missing` kalır
/// ve kullanıcı yeniden bağlar.
public enum FavoriteFileResolver {
    /// - Parameters:
    ///   - fileExists: Relative yol checkout'ta normal bir dosya mı.
    ///   - files: Checkout ağacındaki dosyaların relative yolları; `nil` = ağaç
    ///     henüz yüklenmedi (yer değiştirme aranmaz).
    ///   - excluding: Projenin diğer favorileri — iki favori aynı dosyaya çözülmez.
    public static func locate(
        _ relativePath: String,
        fileExists: (String) -> Bool,
        files: [String]?,
        excluding: Set<String> = []
    ) -> FavoriteFileLocation {
        if fileExists(relativePath) { return .present }
        guard let files,
              let candidate = bestCandidate(for: relativePath, among: files, excluding: excluding),
              fileExists(candidate) else { return .missing }
        return .moved(to: candidate)
    }

    static func bestCandidate(for relativePath: String, among files: [String], excluding: Set<String>) -> String? {
        let name = FavoriteFilePath.name(of: relativePath)
        let candidates = files.filter {
            $0 != relativePath && !excluding.contains($0) && FavoriteFilePath.name(of: $0) == name
        }
        guard candidates.count > 1 else { return candidates.first }
        let oldDirs = directoryComponents(relativePath)
        let scored = candidates.map { ($0, sharedComponents(oldDirs, directoryComponents($0))) }
        guard let best = scored.map(\.1).max() else { return nil }
        let winners = scored.filter { $0.1 == best }
        return winners.count == 1 ? winners[0].0 : nil
    }

    private static func directoryComponents(_ path: String) -> [Substring] {
        Array(path.split(separator: "/").dropLast())
    }

    /// Baştan ve sondan ortak dizin bileşeni sayısı (çakışma sayılmaz).
    private static func sharedComponents(_ lhs: [Substring], _ rhs: [Substring]) -> Int {
        let limit = min(lhs.count, rhs.count)
        var prefix = 0
        while prefix < limit, lhs[prefix] == rhs[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < limit - prefix, lhs[lhs.count - 1 - suffix] == rhs[rhs.count - 1 - suffix] { suffix += 1 }
        return prefix + suffix
    }
}
