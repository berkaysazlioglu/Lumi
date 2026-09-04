import Foundation
import LumiKit
import LumiState

/// Config yan etki dağıtıcısı (design/02 §2, karar 3'ün altyapısı).
///
/// Refactor 3.3: alan başına callback (7 closure + 8 `if` bloğu) yerine
/// **gözlemci listesi**. Koordinatör artık hangi alanın ne yaptığını bilmez;
/// `(old, new)` çiftini kayıtlı gözlemcilere sırayla dağıtır, diff'i her
/// gözlemci kendi alanları için yapar.
///
/// Karar 11 korunur: karşılaştırma EŞİTLİKLE yapılır — Electron'un truthiness
/// bug'ı (0/boş string yan etkiyi atlardı) yapısal olarak imkânsız.
@MainActor
final class ConfigSideEffectCoordinator {
    private let config: any ConfigServicing
    private var observers: [any ConfigChangeObserving] = []
    private let consumer = EventConsumer()

    init(config: any ConfigServicing) {
        self.config = config
    }

    /// Kayıt sırası dağıtım sırasıdır (deterministik yan etki sırası).
    func register(_ observer: any ConfigChangeObserving) {
        observers.append(observer)
    }

    func start() {
        // Stream Task'tan ÖNCE alınır (`events()` nonisolated): abonelik start()
        // dönmeden kuruludur, kurulum penceresinde event kaybolmaz (plan 5.6).
        consumer.start(config.events()) { [weak self] event in
            guard case .configChanged(let old, let new) = event, let self else { return }
            self.dispatch(old: old, new: new)
        }
    }

    func stop() {
        consumer.stop()
    }

    /// Test ve boot yolları için doğrudan dağıtım.
    func dispatch(old: AppConfig, new: AppConfig) {
        for observer in observers {
            observer.configDidChange(old: old, new: new)
        }
    }
}
