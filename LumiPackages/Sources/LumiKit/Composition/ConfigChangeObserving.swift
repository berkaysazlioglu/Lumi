import Foundation

/// Config yan etkilerinin gözlemci sözleşmesi (refactor 3.3).
///
/// `ConfigSideEffectCoordinator` artık alan başına callback taşımaz: tek bir
/// gözlemci listesine `(old, new)` çiftini dağıtır, diff'i her gözlemci kendi
/// alanları için yapar. Karar 11 korunur — karşılaştırma EŞİTLİKLE yapılır,
/// truthiness ile değil, yani `0` / `""` / `false` / `[]` de propagate olur.
@MainActor
public protocol ConfigChangeObserving: AnyObject {
    func configDidChange(old: AppConfig, new: AppConfig)
}
