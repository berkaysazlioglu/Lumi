import Foundation

/// Orta içerik alanının route kimliği (refactor 5.1, K33 ön hazırlığı).
///
/// **Neden `enum case tasks` değil?** Route kümesi Faz 6'da bir registry'den
/// (`ContentRouteRegistry`) beslenecek ve "yeni özellik = yeni dosya + 1 kayıt
/// satırı" hedefi bağlayıcı. Route'ları enum case'i olarak yazsaydık her yeni
/// görünüm LumiKit'teki enum'u ve ondan türeyen tüm exhaustive `switch`'leri
/// değiştirmeye zorlardı (OCP ihlali; bugünkü 11-dosya maliyetinin aynısı).
/// `RawRepresentable` bir id struct'ı ile enum 3 case'te KAPALI kalır, route
/// kümesi AÇIK olur. `PanelItemID` (K33) ile aynı kalıptır ve `rawValue` düz
/// string olduğu için persist tarafı da additive bir string alanına sığar.
public struct ContentRouteID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Kabuğun orta alanında ne gösterildiği (refactor 5.1).
///
/// `.repo` bir repo tab'ıdır (bugünkü tek durum); `.content` repo'dan bağımsız
/// bir görünümdür (Faz 6'da Tasks vb.); `.none` hiçbir tab açık değil demektir.
/// `activeTab: String?` bu tipin `.repo` projeksiyonudur — adaptör
/// `WorkspaceStore` facade'ında yaşar.
public enum WorkspaceRoute: Hashable, Sendable {
    case repo(String)
    case content(ContentRouteID)
    case none

    /// `.repo` projeksiyonu — `onActiveRepoChanged` ve `activeTab` persist'i
    /// bunun üzerinden akar (repo-dışı route → `nil`).
    public var repoPath: String? {
        guard case .repo(let path) = self else { return nil }
        return path
    }

    public var contentRouteID: ContentRouteID? {
        guard case .content(let id) = self else { return nil }
        return id
    }

    public var isRepo: Bool { repoPath != nil }

    /// Legacy adaptör: `String?` → route (nil = `.none`).
    public init(repoPath: String?) {
        self = repoPath.map(WorkspaceRoute.repo) ?? .none
    }
}
