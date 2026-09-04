import Foundation

/// Store yaşam döngüsünün tek kalıbı (refactor 3.4).
///
/// Öncesinde üç farklı kalıp vardı: `start()/stop()` (event tüketen store'lar),
/// `update(_:)/stop()` (zamanlayıcı store'ları) ve hiçbiri. Artık hepsi
/// `start()`/`stop()` ile yönetilir; `update(_:)` yalnız CONFIG DEĞİŞİMİ
/// yoludur (bkz. `SessionScheduleStore`, `UsageAutoRefreshStore`).
///
/// Sözleşme:
/// - `start()` **idempotent**'tir: ikinci çağrı ikinci tüketici kurmaz.
/// - `stop()` **eşzamanlı**dır: döndükten sonra hiçbir event state'i değiştiremez.
/// - `stop()` sonrası `start()` temiz bir tüketiciyle devam eder.
@MainActor
public protocol StoreLifecycle: AnyObject {
    func start() async
    func stop()
}
