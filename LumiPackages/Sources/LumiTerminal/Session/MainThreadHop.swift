import Foundation

/// io queue → MainActor sıçraması. Task yerine main queue kullanılır:
/// main queue FIFO'dur, flush batch'lerinin teslim sırası bozulamaz
/// (spec/00 §4.1-7'nin okuma yolu karşılığı).
func hopToMain(_ body: @escaping @MainActor @Sendable () -> Void) {
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            body()
        }
    }
}
