import Foundation

/// `config.json` → `additionalPaths` girdisi: projeler kökü dışından eklenen
/// tekil repo ya da repo kökü.
///
/// **Persistence yalnız `ConfigCodec` üzerinden — karar 9.**
public struct AdditionalPath: Sendable, Equatable, Identifiable {
    public var id: String
    public var path: String
    public var type: PathType
    public var label: String?

    public enum PathType: String, Sendable {
        case root
        case repo
    }

    public init(id: String, path: String, type: PathType, label: String? = nil) {
        self.id = id
        self.path = path
        self.type = type
        self.label = label
    }
}
