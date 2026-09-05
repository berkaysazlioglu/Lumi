import LumiKit
import SwiftUI

/// Orta alanın bir görünümünün tanımı (K33, Faz 6.3).
///
/// `makeView` yalnız `repoPath`'i alır: `.repo(path)` route'u bunu doldurur,
/// repo-bağımsız route'lar (ileride Tasks) `nil` görür. Store'lar ve aksiyonlar
/// Environment'tan okunur.
public struct ContentRouteDescriptor: Identifiable {
    public let id: ContentRouteID
    public let title: String
    public let icon: String
    public let makeView: @MainActor (String?) -> AnyView

    public init(
        id: ContentRouteID,
        title: String,
        icon: String,
        makeView: @escaping @MainActor (String?) -> AnyView
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.makeView = makeView
    }
}

public extension ContentRouteID {
    /// Terminal ızgarası — kabuğun fallback route'u.
    static let terminals = ContentRouteID("terminals")
}

/// Kayıtlı orta alan route'ları (Faz 6.3/6.6).
///
/// **Saf:** `routes()` kayıt sırasını, `resolve(_:)` bilinmeyen id'de terminals
/// fallback'ini döndürür; ikisi de view render etmeden test edilir.
public struct ContentRouteRegistry {
    private var descriptors: [ContentRouteID: ContentRouteDescriptor] = [:]
    private var registrationOrder: [ContentRouteID] = []

    public init() {}

    public mutating func register(_ descriptor: ContentRouteDescriptor) {
        if descriptors[descriptor.id] == nil {
            registrationOrder.append(descriptor.id)
        }
        descriptors[descriptor.id] = descriptor
    }

    public func routes() -> [ContentRouteDescriptor] {
        registrationOrder.compactMap { descriptors[$0] }
    }

    /// Bilinmeyen route → terminals'a düşer (ui-state'te kalmış eski bir id
    /// kabuğu boş bırakmaz). Terminals de kayıtlı değilse `nil`.
    public func resolve(_ id: ContentRouteID) -> ContentRouteDescriptor? {
        descriptors[id] ?? descriptors[.terminals]
    }
}
