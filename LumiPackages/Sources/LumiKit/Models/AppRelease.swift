import Foundation

/// GitHub Releases'te yayınlanmış bir Lumi sürümü (karar 102).
public struct AppRelease: Sendable, Equatable {
    /// `v` öneki atılmış sürüm (`0.8.1`).
    public let version: AppVersion
    /// Release sayfası — kullanıcı indirmeyi buradan yapar.
    public let pageURL: URL
    public let publishedAt: Date?
    /// Release'e yüklenmiş dosyalar (karar 118: zip + `SHA256SUMS`).
    public let assets: [AppReleaseAsset]
    /// Asset adlarındaki sürüm: tag'in `v`'siz hâli, EKİYLE birlikte
    /// (`0.9.0-rc1`). `version` eki attığı için adları ondan kurmak `-rc`
    /// tag'lerinde zip'i hiç bulamazdı (CI adı `VERSION`'dan, yani tag'den kurar).
    public let assetVersion: String

    public init(
        version: AppVersion,
        pageURL: URL,
        publishedAt: Date?,
        assets: [AppReleaseAsset] = [],
        tag: String? = nil
    ) {
        self.version = version
        self.pageURL = pageURL
        self.publishedAt = publishedAt
        self.assets = assets
        self.assetVersion = tag.map(Self.strippingPrefix) ?? version.description
    }

    private static func strippingPrefix(_ tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "v" || first == "V" else { return trimmed }
        return String(trimmed.dropFirst())
    }

    /// CI'ın mimari başına ürettiği notarize edilmiş zip (`make-app.sh --notarize`).
    public func packageAsset(architecture: String) -> AppReleaseAsset? {
        asset(named: "Lumi-\(assetVersion)-\(architecture)-mac.zip")
    }

    /// Release'in `SHA256SUMS-<sürüm>.txt` dosyası.
    public var checksumsAsset: AppReleaseAsset? {
        asset(named: "SHA256SUMS-\(assetVersion).txt")
    }

    private func asset(named name: String) -> AppReleaseAsset? {
        assets.first { $0.name == name }
    }
}

/// Release'e yüklenmiş tek bir dosya.
public struct AppReleaseAsset: Sendable, Equatable {
    public let name: String
    public let downloadURL: URL

    public init(name: String, downloadURL: URL) {
        self.name = name
        self.downloadURL = downloadURL
    }
}

/// Noktalı sayısal sürüm (`0.8.0`, `v0.8.0`). Eksik bileşen 0 sayılır, böylece
/// `0.8` ile `0.8.0` eşittir. Sayısal olmayan bir değer (`dev`) sürüm DEĞİLDİR.
public struct AppVersion: Sendable, Comparable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        // `0.8.0-beta` gibi ekler karşılaştırmaya girmez.
        let core = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { UInt($0).map { Int($0) } }
        guard !core.isEmpty, numbers.count == parts.count else {
            return nil
        }
        components = numbers
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.padded(to: rhs) == rhs.padded(to: lhs)
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.padded(to: rhs).lexicographicallyPrecedes(rhs.padded(to: lhs))
    }

    private func padded(to other: AppVersion) -> [Int] {
        components + Array(repeating: 0, count: max(0, other.components.count - components.count))
    }
}
