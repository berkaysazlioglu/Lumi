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
    /// Kullanıcının seçtiği terminaller (Custom View, karar 135).
    case custom(CustomViewID)

    /// `.repo` projeksiyonu — repo'ya bağlı eylemler (spawn, hızlı komutlar)
    /// bunun üzerinden akar; `.all` ve `.custom` için `nil`.
    public var repoPath: String? {
        guard case .repo(let path) = self else { return nil }
        return path
    }

    public var customViewID: CustomViewID? {
        guard case .custom(let id) = self else { return nil }
        return id
    }

    /// Bu repo'nun terminalleri kapsamın içinde mi.
    ///
    /// `.custom` üyeliği repo yoluna değil terminal kimliğine bağlıdır ve bu
    /// saf tip onu bilemez: `false` döner. Üyelik sorusunun doğru adresi
    /// `TerminalListStore.contains(_:in:)`'dir.
    public func contains(repoPath: String) -> Bool {
        switch self {
        case .repo(let path): path == repoPath
        case .all: true
        case .custom: false
        }
    }

    public func contains(_ meta: TerminalMeta) -> Bool {
        contains(repoPath: meta.repoPath)
    }
}
