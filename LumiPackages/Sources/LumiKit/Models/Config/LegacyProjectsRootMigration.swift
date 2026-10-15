import Foundation

/// Karar 119: projeler kökü arayüzden kalktı. Mevcut kullanıcının
/// `projectsRoot`'u açılışta bir kez `additionalPaths`'in BAŞINA `root`
/// girdisi olarak taşınır (eski "projeler kökü" grubu listede ilk sıradaydı)
/// ve alan boşaltılır — değer boşaldığı için taşıma kendini tekrar etmez.
/// Aynı klasör zaten ekliyse yeni girdi açılmaz; `repo` tipindeyse `root`'a
/// yükseltilir (yoksa kökün alt klasör taraması kaybolurdu).
public enum LegacyProjectsRootMigration {
    public static func migrate(_ config: inout AppConfig) {
        guard hasRoot(config.projectsRoot) else { return }
        let root = config.projectsRoot.trimmingCharacters(in: .whitespaces)
        // Kökü olan kullanıcı onboarding'i geçmiştir; boşalan alan bunu
        // artık türetemez, bu yüzden açık değer yazılır.
        config.onboardingCompleted = true
        if let index = config.additionalPaths.firstIndex(where: { AdditionalPath.isSameFolder($0.path, root) }) {
            config.additionalPaths[index].type = .root
        } else {
            config.additionalPaths.insert(AdditionalPath(id: UUID().uuidString, path: root, type: .root), at: 0)
        }
        config.projectsRoot = ""
    }

    /// Legacy kök dolu mu — codec'in onboarding çıkarımı da bu kuralı kullanır.
    public static func hasRoot(_ projectsRoot: String) -> Bool {
        !projectsRoot.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

public extension AdditionalPath {
    /// `path`'i listeye ekler; aynı klasör zaten varsa liste aynen döner.
    /// `id` dışarıdan verilebilir: `SettingsStore.apply` closure'ı iki kez
    /// koşar (optimistik + disk) ve iki ayrı UUID store ile diski ayrıştırırdı.
    static func adding(
        _ path: String,
        type: PathType,
        to paths: [AdditionalPath],
        id: String = UUID().uuidString
    ) -> [AdditionalPath] {
        guard !paths.contains(where: { isSameFolder($0.path, path) }) else { return paths }
        return paths + [AdditionalPath(id: id, path: path, type: type)]
    }

    /// Tilde ve son eğik çizgi farkı gözetilmeden aynı klasör mü.
    static func isSameFolder(_ lhs: String, _ rhs: String) -> Bool {
        normalized(lhs) == normalized(rhs)
    }

    private static func normalized(_ path: String) -> String {
        ((path as NSString).expandingTildeInPath as NSString).standardizingPath
    }
}
