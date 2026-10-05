import Foundation
import LumiKit
import Observation

/// Proje favori dosyaları (karar 107).
///
/// Tek doğruluk kaynağı `config.json`'daki `projectFavoriteFiles`'tır; store
/// yazdıktan sonra diskteki hâli geri okur, dış değişiklikler `update(_:)`
/// ile (config yan etkisi) gelir — `QuickCommandStore` kalıbı.
///
/// Silinen/taşınan dosya: liste her çizimde diske sorulur
/// (`entries(projectPath:checkoutPath:tree:)`). Kayıtlı yolda dosya yoksa
/// `FavoriteFileResolver` ağaçta yeni yerini arar; bulunursa satır oradan
/// açılır, bulunamazsa "missing" çizilir ve açma eylemleri kapanır. Taşınma
/// yalnız projenin KENDİ kökünde kalıcı yazılır (`persistMoves`): yönetilen
/// bir workspace başka bir dalda olabilir, oradaki taşınmayı kaydetmek
/// `main`'deki yolu bozardı.
@Observable
@MainActor
public final class FavoriteFileStore {
    public private(set) var favorites: [ProjectFavoriteFile] = []
    @ObservationIgnored private let config: any ConfigServicing
    @ObservationIgnored private let toasts: ToastStore
    @ObservationIgnored private let fileExists: @Sendable (String) -> Bool

    public init(
        config: any ConfigServicing,
        toasts: ToastStore,
        fileExists: @escaping @Sendable (String) -> Bool = FavoriteFileStore.isRegularFile
    ) {
        self.config = config
        self.toasts = toasts
        self.fileExists = fileExists
    }

    /// Mutlak yol normal bir dosya mı (klasör ya da yok → false).
    public nonisolated static func isRegularFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    public func load() async {
        update(await config.config().projectFavoriteFiles)
    }

    public func update(_ favorites: [ProjectFavoriteFile]) {
        self.favorites = favorites
    }

    /// Projenin favorileri, eklendikleri sırayla.
    public func favorites(for projectPath: String) -> [ProjectFavoriteFile] {
        favorites.filter { $0.projectPath == projectPath }
    }

    public func isFavorite(_ relativePath: String, in projectPath: String) -> Bool {
        favorites.contains { $0.projectPath == projectPath && $0.relativePath == relativePath }
    }

    public func fileExists(_ relativePath: String, in checkoutPath: String) -> Bool {
        fileExists(FavoriteFilePath.absolute(relativePath, in: checkoutPath))
    }

    // MARK: - Çözümleme

    /// Menü satırları: her favori aktif checkout'ta çözülür. `tree` checkout'un
    /// dosya ağacıdır (`nil` = henüz yüklenmedi; taşınma aranmaz). Ağaç yalnız
    /// kayıtlı yolunda bulunmayan favori varsa düzleştirilir.
    public func entries(projectPath: String, checkoutPath: String, tree: [FileTreeNode]?) -> [FavoriteFileEntry] {
        let projectFavorites = favorites(for: projectPath)
        let exists: (String) -> Bool = { [fileExists] in
            fileExists(FavoriteFilePath.absolute($0, in: checkoutPath))
        }
        var files: [String]?
        return projectFavorites.map { favorite in
            guard !exists(favorite.relativePath) else {
                return FavoriteFileEntry(favorite: favorite, location: .present)
            }
            if files == nil, let tree { files = FavoriteFileSearch.filePaths(in: tree) }
            let others = Set(projectFavorites.lazy.filter { $0.id != favorite.id }.map(\.relativePath))
            let location = FavoriteFileResolver.locate(
                favorite.relativePath, fileExists: exists, files: files, excluding: others
            )
            return FavoriteFileEntry(favorite: favorite, location: location)
        }
    }

    /// Taşındığı anlaşılan favorilerin yeni yolunu kalıcı yazar. Çağıran yalnız
    /// projenin kendi kökündeki çözümlemeyi verir (bkz. tip dokümanı).
    public func persistMoves(_ entries: [FavoriteFileEntry]) async {
        let moves: [String: String] = Dictionary(
            entries.compactMap { entry in
                guard case .moved(let path) = entry.location else { return nil }
                return (entry.favorite.id, path)
            },
            uniquingKeysWith: { first, _ in first }
        )
        guard !moves.isEmpty else { return }
        await write(failureTitle: "Favorite could not be updated") { config in
            for index in config.projectFavoriteFiles.indices {
                if let path = moves[config.projectFavoriteFiles[index].id] {
                    config.projectFavoriteFiles[index].relativePath = path
                }
            }
        }
    }

    // MARK: - Düzenleme

    /// Sona ekler; aynı dosya zaten favoriyse yazmaz.
    @discardableResult
    public func add(_ relativePath: String, to projectPath: String) async -> Bool {
        let favorite = ProjectFavoriteFile(projectPath: projectPath, relativePath: relativePath)
        guard favorite.isValid, !isFavorite(relativePath, in: projectPath) else { return false }
        return await write(failureTitle: "Favorite could not be added") { config in
            guard !config.projectFavoriteFiles.contains(where: {
                $0.projectPath == projectPath && $0.relativePath == relativePath
            }) else { return }
            config.projectFavoriteFiles.append(favorite)
        }
    }

    /// Ekliyse çıkarır, değilse ekler (arama sonucundaki yıldız).
    @discardableResult
    public func toggle(_ relativePath: String, in projectPath: String) async -> Bool {
        if let existing = favorites.first(where: { $0.projectPath == projectPath && $0.relativePath == relativePath }) {
            return await remove(id: existing.id)
        }
        return await add(relativePath, to: projectPath)
    }

    @discardableResult
    public func remove(id: String) async -> Bool {
        await write(failureTitle: "Favorite could not be removed") { config in
            config.projectFavoriteFiles.removeAll { $0.id == id }
        }
    }

    /// Kayıp favoriyi elle yeni yerine bağlar. Hedef zaten favoriyse eski kayıt
    /// düşer (aynı dosya iki kez listelenmez).
    @discardableResult
    public func relink(id: String, to relativePath: String) async -> Bool {
        guard FavoriteFilePath.isValidRelative(relativePath) else { return false }
        return await write(failureTitle: "Favorite could not be updated") { config in
            guard let index = config.projectFavoriteFiles.firstIndex(where: { $0.id == id }) else { return }
            let projectPath = config.projectFavoriteFiles[index].projectPath
            let isDuplicate = config.projectFavoriteFiles.contains {
                $0.id != id && $0.projectPath == projectPath && $0.relativePath == relativePath
            }
            if isDuplicate {
                config.projectFavoriteFiles.remove(at: index)
            } else {
                config.projectFavoriteFiles[index].relativePath = relativePath
            }
        }
    }

    @discardableResult
    private func write(failureTitle: String, _ mutate: @escaping @Sendable (inout AppConfig) -> Void) async -> Bool {
        do {
            try await config.updateConfig(mutate)
            update(await config.config().projectFavoriteFiles)
            return true
        } catch {
            toasts.show(.error, title: failureTitle, message: error.localizedDescription)
            return false
        }
    }
}
