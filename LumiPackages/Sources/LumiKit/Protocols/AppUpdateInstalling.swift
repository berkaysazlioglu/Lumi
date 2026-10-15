import Foundation

/// Yeni sürümü indirip doğrulayan ve Lumi kapanınca kuran servis yüzü
/// (karar 118).
public protocol AppUpdateInstalling: Sendable {
    /// Çalışan kopyanın kendini güncelleyip güncelleyemeyeceği. Senkron ve
    /// ucuzdur (imza + dosya izni) — store kurulurken bir kez sorulur.
    func installSupport() -> AppUpdateInstallSupport

    /// Release'in bu mimariye ait zip'ini indirir, `SHA256SUMS`'la ve Developer
    /// ID imzasıyla doğrular, açar. Aynı sürüm daha önce sahnelenmişse
    /// yeniden indirmez. Hata `LumiError.updateInstallFailed` olur.
    func prepare(_ release: AppRelease) async throws -> StagedAppUpdate

    /// Lumi'nin sürecinin bitmesini bekleyip sahnelenen sürümü yerine kuran
    /// tek seferlik LaunchAgent'ı kaydeder. Lumi'nin kapanış yolunda çağrılır.
    func scheduleInstall(_ update: StagedAppUpdate, relaunch: Bool) async throws

    /// Önceki kurulum denemesi başarısız olduysa nedenini döndürür ve kaydı
    /// siler (bir kez gösterilir).
    func consumeInstallFailure() async -> String?

    /// `keep` dışındaki sahnelenmiş sürümleri siler (`nil` → hepsini): yeni
    /// sürüm hazır olunca eskisi, release geri çekilince hepsi.
    func discardStaged(except keep: StagedAppUpdate?) async
}
