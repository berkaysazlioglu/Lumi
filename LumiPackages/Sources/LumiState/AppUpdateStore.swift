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
/// **Daha yeni sürüm hazır olanın yerini alır.** Hazır bir sürüm varken daha
/// yenisi çıkarsa arka planda indirilir; hazır olan bu sırada görünmeye
/// devam eder, yenisi doğrulanınca yerine geçer ve eskisi diskten ancak O
/// ZAMAN silinir. Kurulum kaydedildiyse (`isInstallCommitted`: Restart Now ya
/// da kapanış) değiştirme yapılmaz — kaydedilen sahne altından silinemez.
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
    /// Hazır sürüm dururken daha yenisi arka planda indiriliyor.
    public private(set) var isDownloadingNewer = false
    /// Kurulum agent'a kaydedildi ya da kaydediliyor — sahne artık değişmez.
    @ObservationIgnored private var isInstallCommitted = false

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
    /// buradan geçer. İndirme sürerken no-op.
    public func check() async {
        guard !isChecking, !isDownloadingNewer else { return }
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
        // Release geri çekildiyse (silindi; `latest` hazır sürümden küçük) hazır
        // sürüm de gider — kart, segment ve quit'te kurulum artık önerilmez.
        if let staged = stagedUpdate, latest.version < staged.release.version {
            guard !isInstallCommitted else { return } // kapanış başladı
            installTiming = nil
            status = .idle
            await installer.discardStaged(except: nil)
        }
        guard latest.version > current else {
            status = .upToDate(latest)
            return
        }
        if let staged = stagedUpdate {
            if latest.version > staged.release.version { await replaceStaged(with: latest) }
            return
        }
        guard installSupport.isSupported else {
            status = .available(latest)
            return
        }
        await download(latest)
    }

    private func download(_ release: AppRelease) async {
        status = .downloading(release)
        do {
            let staged = try await installer.prepare(release)
            status = .readyToInstall(staged)
            await installer.discardStaged(except: staged)
        } catch {
            status = .downloadFailed(release, message: error.localizedDescription)
        }
    }

    /// Hazır sürüm görünmeye devam ederken daha yenisini indirir; yenisi
    /// hazır olunca yerine geçer (seçilmiş `Install on Quit` yenisine uygulanır,
    /// kart yeni sürüm için yeniden çıkar). Hata olursa hazır olan kalır, bir
    /// sonraki kontrol yeniden dener.
    private func replaceStaged(with release: AppRelease) async {
        guard !isInstallCommitted, installSupport.isSupported else { return }
        isDownloadingNewer = true
        defer { isDownloadingNewer = false }
        guard let newer = try? await installer.prepare(release) else { return }
        // İndirme sürerken kurulum kaydedildiyse kayıtlı sahneye dokunulmaz;
        // yeni dosyalar bir sonraki temizlikte gider.
        guard !isInstallCommitted, stagedUpdate != nil else { return }
        status = .readyToInstall(newer)
        await installer.discardStaged(except: newer)
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
        isInstallCommitted = true
        defer { isSchedulingRestart = false }
        do {
            try await installer.scheduleInstall(staged, relaunch: true)
        } catch {
            isInstallCommitted = false
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
        isInstallCommitted = true
        do {
            try await installer.scheduleInstall(staged, relaunch: false)
            return true
        } catch {
            lastInstallFailure = error.localizedDescription
            return false
        }
    }
}
