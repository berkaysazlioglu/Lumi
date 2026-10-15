import Foundation
import LumiKit
import Observation

/// Yeni sürüm kontrolü (karar 102) ve uygulama içi güncelleme (karar 118) —
/// Settings ▸ About'un, sağ alttaki kartın ve alt bar segmentinin tek kaynağı.
///
/// Akış: kontrol (açılışta + `checkInterval`'da bir) → daha yeni sürüm varsa
/// sessizce indir + doğrula → `readyToInstall` (kart görünür) → kullanıcı
/// dialogda seçer: `Restart Now` kurulumu ÖNCE kaydeder, ancak kayıt
/// başarılıysa kapanışı başlatır; `Install on Quit` kaydı Lumi'nin kapanış
/// yoluna bırakır (`installIfScheduled`). Kendiliğinden hiçbir zaman kapatmaz
/// ya da kurmaz.
///
/// **Hazır sürüm oturum boyunca sabittir.** Daha yeni bir sürüm çıksa da
/// hazır olanın yerine bu oturumda indirilmez — bir sonraki açılış alır.
/// Böylece kullanıcının seçtiği (ya da seçmek üzere olduğu) sahne, uçuştaki
/// bir kontrolün altından silinemez.
///
/// Hata toast olmaz (ağsız açılış kullanıcıyı rahatsız etmemeli), About'ta
/// satır içi görünür. `dev` build `.developmentBuild` olur, "güncelle" denmez.
@Observable
@MainActor
public final class AppUpdateStore {
    public enum Status: Equatable {
        case idle
        case checking
        case upToDate(AppRelease)
        /// Daha yeni sürüm var ama bu kopya kendini güncelleyemiyor
        /// (`installSupport`) — kullanıcı release sayfasından indirir.
        case available(AppRelease)
        case downloading(AppRelease)
        case readyToInstall(StagedAppUpdate)
        case downloadFailed(AppRelease, message: String)
        /// Çalışan build sürüm taşımıyor (`dev`); son yayın yalnız bilgi.
        case developmentBuild(AppRelease)
        case failed(message: String)
    }

    /// Kontrol aralığı (karar 118). GitHub'ın yetkisiz sınırı saatte 60 istek.
    public static let checkInterval: Duration = .seconds(4 * 60 * 60)

    public let currentVersion: String
    public let installSupport: AppUpdateInstallSupport
    public private(set) var status: Status = .idle
    public private(set) var isChecking = false
    public private(set) var lastCheckedAt: Date?
    /// Kullanıcının seçtiği kurulum zamanı; `nil` → henüz karar yok.
    public private(set) var installTiming: AppUpdateInstallTiming?
    /// Kartı bu oturumda kapatılan sürüm. Kalıcı değildir: bir sonraki açılış
    /// hatırlatır, alt bar segmenti ise hep görünür kalır.
    public private(set) var dismissedVersion: AppVersion?
    /// Önceki kurulum denemesinin hatası (installer script'i yazar).
    public private(set) var lastInstallFailure: String?
    /// `Restart Now` kurulumu kaydederken (çift tıklamaya karşı).
    public private(set) var isSchedulingRestart = false

    /// `Restart Now` — kapanışı başlatan kabuk köprüsü (AppKit LumiState'te yok).
    @ObservationIgnored public var onRestartRequested: (@MainActor () -> Void)?

    @ObservationIgnored private let service: any AppReleaseChecking
    @ObservationIgnored private let installer: any AppUpdateInstalling
    @ObservationIgnored private let now: @MainActor () -> Date

    public init(
        currentVersion: String,
        service: any AppReleaseChecking,
        installer: any AppUpdateInstalling,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.currentVersion = currentVersion
        self.service = service
        self.installer = installer
        self.installSupport = installer.installSupport()
        self.now = now
    }

    // MARK: - Türevler

    /// Bilinen daha yeni sürüm (hangi aşamada olursa olsun).
    public var availableRelease: AppRelease? {
        switch status {
        case .available(let release), .downloading(let release), .downloadFailed(let release, _):
            release
        case .readyToInstall(let staged):
            staged.release
        case .idle, .checking, .upToDate, .developmentBuild, .failed:
            nil
        }
    }

    public var stagedUpdate: StagedAppUpdate? {
        guard case .readyToInstall(let staged) = status else { return nil }
        return staged
    }

    /// Sağ alttaki kart: kurulmaya hazır sürüm ya da (kendini güncelleyemeyen
    /// ama kullanıcının düzeltebileceği bir konumdaki kopya için) elle indirme
    /// çağrısı. Kurulum zamanı seçildiyse kart işini bitirmiştir.
    public var isCardVisible: Bool {
        guard installTiming == nil, let release = availableRelease,
              release.version != dismissedVersion
        else { return false }
        switch status {
        case .readyToInstall: return true
        case .available: return installSupport != .unsignedBuild
        default: return false
        }
    }

    // MARK: - Kontrol

    /// Açılışta ve `checkInterval`'da bir koşar; About'taki buton ve menü de
    /// buradan geçer. İndirme sürerken no-op; hazır bir sürüm varken yalnız
    /// kontrol zamanını tazeler (sahneye dokunmaz).
    public func check() async {
        guard !isChecking else { return }
        if case .downloading = status { return }
        isChecking = true
        defer { isChecking = false }
        // Hazır bir sürüm varken kart/segment kontrol boyunca sönmesin.
        if stagedUpdate == nil { status = .checking }
        do {
            let latest = try await service.latestRelease()
            lastCheckedAt = now()
            await apply(latest)
        } catch {
            lastCheckedAt = now()
            if stagedUpdate == nil { status = .failed(message: error.localizedDescription) }
        }
    }

    public func retryDownload() async {
        guard case .downloadFailed(let release, _) = status else { return }
        await download(release)
    }

    /// Önceki açılışta yarım kalan kurulumun hatasını bir kez alır.
    public func loadInstallFailure() async {
        lastInstallFailure = await installer.consumeInstallFailure()
    }

    private func apply(_ latest: AppRelease) async {
        guard let current = AppVersion(currentVersion) else {
            status = .developmentBuild(latest)
            return
        }
        guard latest.version > current else {
            status = .upToDate(latest)
            return
        }
        // Oturum boyunca sabit (bkz. tip yorumu) — `await`'ten sonra da geçerli.
        if stagedUpdate != nil { return }
        guard installSupport.isSupported else {
            status = .available(latest)
            return
        }
        await download(latest)
    }

    private func download(_ release: AppRelease) async {
        status = .downloading(release)
        do {
            status = .readyToInstall(try await installer.prepare(release))
        } catch {
            status = .downloadFailed(release, message: error.localizedDescription)
        }
    }

    // MARK: - Kurulum seçimi

    public func dismissCard() {
        dismissedVersion = availableRelease?.version
    }

    /// Lumi bir sonraki kapanışında kurulur (yeniden açılmaz).
    public func installOnQuit() {
        guard stagedUpdate != nil else { return }
        installTiming = .onQuit
    }

    public func cancelScheduledInstall() {
        installTiming = nil
    }

    /// Kurulumu kaydeder, ANCAK başarılıysa kapanışı başlatır: kayıt
    /// başarısız olursa Lumi açık kalır ve hata kartta görünür (kapanıp hiç
    /// geri gelmemesi yerine). Agent Lumi'nin PID'ini beklediği için erken
    /// kayıt güvenlidir.
    public func restartNow() async {
        guard let staged = stagedUpdate, !isSchedulingRestart else { return }
        isSchedulingRestart = true
        defer { isSchedulingRestart = false }
        do {
            try await installer.scheduleInstall(staged, relaunch: true)
        } catch {
            lastInstallFailure = error.localizedDescription
            return
        }
        lastInstallFailure = nil
        installTiming = .restartNow
        onRestartRequested?()
    }

    /// Kapanış yolunun kancası: `Install on Quit` seçildiyse LaunchAgent'ı
    /// kaydeder (yeniden açmadan). `Restart Now` kaydını zaten yapmıştır.
    /// Hata olursa uygulama yine kapanır; installer hatayı diske yazar,
    /// bir sonraki açılışın kartı gösterir.
    @discardableResult
    public func installIfScheduled() async -> Bool {
        guard installTiming == .onQuit, let staged = stagedUpdate else { return false }
        do {
            try await installer.scheduleInstall(staged, relaunch: false)
            return true
        } catch {
            lastInstallFailure = error.localizedDescription
            return false
        }
    }
}
