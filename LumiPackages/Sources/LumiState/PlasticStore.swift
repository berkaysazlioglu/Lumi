import Foundation
import LumiKit
import Observation

/// Plastic SCM panel cache'leri (karar 45): çalışma alanı başlığı, değişiklik
/// listesi ve son changeset'ler. Salt-okunur; commit/checkin yok.
///
/// Tazeleme: aktif repo değişiminde `loadAll`, FSEvents köprüsünde yalnız
/// `refreshStatus` (changeset sorgusu sunucuya gider — her dosya
/// değişiminde koşmaz), başlıktaki ↻ ile yeniden `loadAll`.
@Observable
@MainActor
public final class PlasticStore {
    /// History'de gösterilen pencere: son 7 gün.
    public static let recentWindow: TimeInterval = 7 * 24 * 60 * 60
    /// Sunucudan çekilen en yeni changeset tavanı; pencere bunun içinde uygulanır.
    public static let changesetLimit = 200
    /// Pencerede hiç changeset yoksa gösterilen en yeni N kayıt.
    public static let fallbackCount = 25

    /// History gövdesinin verisi: pencere içindekiler ya da (boşsa) en yeniler.
    public struct RecentChangesets: Equatable, Sendable {
        public let items: [PlasticChangeset]
        /// true → pencere boştu, `items` en yeni `fallbackCount` kayıttır.
        public let isFallback: Bool

        public init(items: [PlasticChangeset], isFallback: Bool) {
            self.items = items
            self.isFallback = isFallback
        }

        public static let empty = RecentChangesets(items: [], isFallback: false)
    }

    public private(set) var workspaces: [String: PlasticWorkspaceInfo] = [:]
    public private(set) var changesets: [String: [PlasticChangeset]] = [:]
    public private(set) var changes: [String: [PlasticFileChange]] = [:]
    /// `cm` kurulu mu? Süreç ömrü boyunca bir kez ölçülür.
    public private(set) var isCLIAvailable = true
    @ObservationIgnored private var didProbeCLI = false
    public private(set) var loadingPaths: Set<String> = []

    @ObservationIgnored private let service: any PlasticReading
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(service: any PlasticReading, now: @escaping @Sendable () -> Date = { Date() }) {
        self.service = service
        self.now = now
    }

    // MARK: - Yükleme

    public func loadAll(_ workspacePath: String) async {
        loadingPaths.insert(workspacePath)
        defer { loadingPaths.remove(workspacePath) }

        if !didProbeCLI {
            didProbeCLI = true
            isCLIAvailable = await service.isCLIAvailable()
        }
        guard isCLIAvailable else { return }

        if let info = await service.workspaceInfo(workspacePath: workspacePath) {
            workspaces[workspacePath] = info
        } else {
            workspaces.removeValue(forKey: workspacePath)
        }
        changes[workspacePath] = await service.status(workspacePath: workspacePath)
        changesets[workspacePath] = await service.recentChangesets(
            workspacePath: workspacePath, limit: Self.changesetLimit
        )
    }

    /// FSEvents köprüsü: yalnız çalışma alanı durumu (sunucu sorgusu yok).
    public func refreshStatus(_ workspacePath: String) async {
        guard isCLIAvailable else { return }
        changes[workspacePath] = await service.status(workspacePath: workspacePath)
    }

    public func isLoading(_ workspacePath: String) -> Bool {
        loadingPaths.contains(workspacePath)
    }

    // MARK: - Türevler

    public func recentChangesets(_ workspacePath: String) -> RecentChangesets {
        Self.select(from: changesets[workspacePath] ?? [], now: now())
    }

    /// Saf seçim: `now - recentWindow`dan yeni olanlar; hiç yoksa en yeni
    /// `fallbackCount` kayıt `isFallback` bayrağıyla. Giriş yeniden eskiye
    /// sıralı varsayılır; çıktı da öyle sıralanır.
    public static func select(from all: [PlasticChangeset], now: Date) -> RecentChangesets {
        let sorted = all.sorted { $0.date > $1.date }
        let cutoff = now.addingTimeInterval(-recentWindow)
        let recent = sorted.filter { $0.date >= cutoff }
        if !recent.isEmpty { return RecentChangesets(items: recent, isFallback: false) }
        return RecentChangesets(items: Array(sorted.prefix(fallbackCount)), isFallback: !sorted.isEmpty)
    }

    // MARK: - Cache eviction

    public func evict(_ workspacePath: String) {
        workspaces.removeValue(forKey: workspacePath)
        changesets.removeValue(forKey: workspacePath)
        changes.removeValue(forKey: workspacePath)
        loadingPaths.remove(workspacePath)
    }
}
