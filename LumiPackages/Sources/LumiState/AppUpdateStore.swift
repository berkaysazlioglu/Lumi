import Foundation
import LumiKit
import Observation

/// Yeni sürüm kontrolü (karar 102) — Settings ▸ About'un ve sekme rozetinin
/// tek kaynağı.
///
/// Açılışta bir kez sessizce sorulur; hata toast olmaz (ağsız açılış kullanıcıyı
/// rahatsız etmemeli), About'ta satır içi görünür. Sürüm karşılaştırması
/// yalnız paketlenmiş build'de anlamlıdır: `swift run`'ın `dev` sürümü
/// `.developmentBuild` olur, "güncelle" denmez.
@Observable
@MainActor
public final class AppUpdateStore {
    public enum Status: Equatable {
        case idle
        case checking
        case upToDate(AppRelease)
        case available(AppRelease)
        /// Çalışan build sürüm taşımıyor (`dev`); son yayın yalnız bilgi.
        case developmentBuild(AppRelease)
        case failed(message: String)
    }

    public let currentVersion: String
    public private(set) var status: Status = .idle
    public private(set) var lastCheckedAt: Date?

    @ObservationIgnored private let service: any AppReleaseChecking
    @ObservationIgnored private let now: @MainActor () -> Date

    public init(
        currentVersion: String,
        service: any AppReleaseChecking,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.currentVersion = currentVersion
        self.service = service
        self.now = now
    }

    public var isChecking: Bool { status == .checking }

    public var availableRelease: AppRelease? {
        if case .available(let release) = status { return release }
        return nil
    }

    public func check() async {
        guard !isChecking else { return }
        status = .checking
        do {
            let latest = try await service.latestRelease()
            status = Self.status(current: currentVersion, latest: latest)
        } catch {
            status = .failed(message: error.localizedDescription)
        }
        lastCheckedAt = now()
    }

    static func status(current: String, latest: AppRelease) -> Status {
        guard let currentVersion = AppVersion(current) else { return .developmentBuild(latest) }
        return latest.version > currentVersion ? .available(latest) : .upToDate(latest)
    }
}
