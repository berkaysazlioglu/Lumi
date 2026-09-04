import Foundation
import LumiKit

/// Bootstrap fazları (refactor 3.3). `start()` artan, `shutdown()` azalan
/// sırada koşar — böylece "önce kurulan sonra yıkılır" simetrisi bedavaya gelir.
public enum BootstrapPhase: Int, Sendable, Comparable, CaseIterable {
    /// Spawn'dan ve config okumasından önce kurulması gerekenler (terminal).
    case system = 0
    /// Config'ten beslenen yan sistemler (bildirim, zamanlama, kullanım).
    case config = 1
    /// Repo keşfi + repoya bağlı veriler; workspace'i besler.
    case repo = 2
    /// Repo/workspace yüklendikten SONRA anlamlı olan UI durumu.
    case ui = 3

    public static func < (lhs: BootstrapPhase, rhs: BootstrapPhase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Bir özelliğin composition birimi (refactor 3.3, K36).
///
/// Servis + store + yan etki + yaşam döngüsü TEK dosyada toplanır; `AppContainer`
/// yalnızca faz sırasına göre `build → start → configDidChange → shutdown`
/// çağıran ince bir koşucudur ve hiçbir feature'ı tanımaz. Yeni özellik eklemek
/// = yeni bir assembly dosyası + composition listesine bir satır.
///
/// `ConfigChangeObserving` mirası: config yan etkisi artık koordinatörde alan
/// başına callback değil, her assembly'nin kendi diff'idir (karar 11 eşitlik
/// tabanlı diff kuralı assembly içinde korunur).
@MainActor
public protocol FeatureAssembly: AnyObject, ConfigChangeObserving {
    var bootstrapPhase: BootstrapPhase { get }

    /// Bağımlılıkları alır ve store'larını kurar. İŞ YAPMAZ (design/00 §3:
    /// "tüm servis + store'lar; henüz iş yapılmaz").
    func build(services: any ServiceRegistry, shared: SharedStores)

    /// Faz sırasında çalışan bootstrap işi: config okuma, store lifecycle,
    /// event köprüleri.
    func start() async

    /// `start()` ile simetrik yıkım.
    func shutdown() async
}

public extension FeatureAssembly {
    /// Config yan etkisi olmayan assembly'ler için varsayılan.
    func configDidChange(old: AppConfig, new: AppConfig) {}
}
