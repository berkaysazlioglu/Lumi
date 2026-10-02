import Foundation

/// GitHub Releases'te yayınlanmış bir Lumi sürümü (karar 102).
public struct AppRelease: Sendable, Equatable {
    /// `v` öneki atılmış sürüm (`0.8.1`).
    public let version: AppVersion
    /// Release sayfası — kullanıcı indirmeyi buradan yapar.
    public let pageURL: URL
    public let publishedAt: Date?

    public init(version: AppVersion, pageURL: URL, publishedAt: Date?) {
        self.version = version
        self.pageURL = pageURL
        self.publishedAt = publishedAt
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
