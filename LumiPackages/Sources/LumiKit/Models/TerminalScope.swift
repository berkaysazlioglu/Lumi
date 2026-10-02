import Foundation

/// Terminal yüzeyinin hangi terminalleri kapsadığı (karar 103).
///
/// Karar 103 öncesinde yüzey her yerde "bir repo" demekti; All Terminals
/// görünümü aynı grid/maximize/minimize/Edit davranışını tüm projelerin
/// terminalleri üzerinde ister. Yüzeyle konuşan her sorgu ve intent repo yolu
/// yerine bu kapsamı alır; `.repo` eski davranışın birebir karşılığıdır.
public enum TerminalScope: Hashable, Sendable {
    /// Tek bir checkout'un terminalleri (repo route'u).
    case repo(String)
    /// Tüm projelerin terminalleri (All Terminals route'u).
    case all

    /// `.repo` projeksiyonu — repo'ya bağlı eylemler (spawn, hızlı komutlar)
    /// bunun üzerinden akar; `.all` için `nil`.
    public var repoPath: String? {
        guard case .repo(let path) = self else { return nil }
        return path
    }

    /// Bu repo'nun terminalleri kapsamın içinde mi.
    public func contains(repoPath: String) -> Bool {
        switch self {
        case .repo(let path): path == repoPath
        case .all: true
        }
    }

    public func contains(_ meta: TerminalMeta) -> Bool {
        contains(repoPath: meta.repoPath)
    }
}
