import Foundation
import LumiKit
import Observation

/// Karar 108: All Terminals'tan açılan projesiz ("serbest") terminallerin
/// konumu.
///
/// Geçerli konum son seçilen/kullanılan konumdur (`recentLocations.first`),
/// hiç seçilmemişse ev dizini — kökü olmayan kullanıcı da tek tıkla terminal
/// açabilsin diye. Liste `ui-state.json` → `recentLooseLocations`'a additive
/// olarak yazılır (karar 9).
@Observable
@MainActor
public final class LooseTerminalStore {
    public private(set) var recentLocations: [String] = []

    @ObservationIgnored private let config: any ConfigServicing
    @ObservationIgnored private let toasts: ToastStore
    @ObservationIgnored private let home: String
    @ObservationIgnored private let directoryExists: (String) -> Bool
    /// Persist zincirinin kuyruğu — geç kalan bayat yazım en son diske inmesin.
    @ObservationIgnored private var pendingPersistTask: Task<Void, Never>?

    public init(
        config: any ConfigServicing,
        toasts: ToastStore,
        home: String = NSHomeDirectory(),
        directoryExists: @escaping (String) -> Bool = LooseTerminalStore.isDirectory
    ) {
        self.config = config
        self.toasts = toasts
        self.home = home
        self.directoryExists = directoryExists
    }

    public func load(recent: [String]) {
        recentLocations = recent
    }

    /// Yeni serbest terminalin açılacağı konum.
    public var currentLocation: String {
        LooseTerminalPath.normalized(recentLocations.first ?? home, home: home)
    }

    public var currentLocationLabel: String {
        LooseTerminalPath.displayLabel(currentLocation, home: home)
    }

    public func candidates(for config: AppConfig) -> [LooseTerminalLocation] {
        LooseTerminalLocations.candidates(
            projectsRoot: config.projectsRoot,
            additionalPaths: config.additionalPaths,
            recent: recentLocations,
            home: home
        )
    }

    /// Konumu geçerli yapar (ve son kullanılanların başına alır).
    public func select(_ path: String) {
        let updated = LooseTerminalLocations.recording(path, into: recentLocations, home: home)
        guard updated != recentLocations else { return }
        recentLocations = updated
        persist()
    }

    /// Spawn kapısı: geçerli konum hâlâ bir dizinse onu döner. Silinmiş/taşınmış
    /// konum listeden düşer, kullanıcı uyarılır ve terminal açılmaz — sessizce
    /// başka bir yerde açmak, ajanın yanlış dizinde çalışması demekti.
    public func locationForSpawn() -> String? {
        let location = currentLocation
        guard directoryExists(location) else {
            toasts.show(
                .error,
                title: "Folder not found",
                message: "\(LooseTerminalPath.displayLabel(location, home: home)) no longer exists. Pick another location."
            )
            forget(location)
            return nil
        }
        return location
    }

    private func forget(_ path: String) {
        let updated = recentLocations.filter { LooseTerminalPath.normalized($0, home: home) != path }
        guard updated != recentLocations else { return }
        recentLocations = updated
        persist()
    }

    private func persist() {
        let snapshot = recentLocations
        let previous = pendingPersistTask
        pendingPersistTask = Task { [config] in
            await previous?.value
            await config.updateUIState { $0.recentLooseLocations = snapshot }
        }
    }

    /// Test bekleme noktası: son yazım diske indi mi.
    public func flushPersistence() async {
        await pendingPersistTask?.value
    }

    public nonisolated static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
