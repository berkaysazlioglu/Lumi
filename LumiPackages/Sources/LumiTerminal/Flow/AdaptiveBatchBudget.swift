import Foundation

/// Coalescer'ın boyut eşiğinin uyarlanabilir hâli (design/00 Ek A §A.2-10,
/// design/01 §8 "flush boyut eşiği knob'u"): feed main thread'de 4 ms bütçeyi
/// aşarsa eşik yarıya iner (daha küçük batch = daha kısa feed), normale
/// dönüldükçe kademeli olarak (her bütçe-içi feed'de iki katı) geri açılır.
///
/// io queue'dan (okuma) ve MainActor'dan (feed ölçümü) dokunulur — lock korumalı.
final class AdaptiveBatchBudget: @unchecked Sendable {
    /// Alt sınır: bunun altında flush başına MainActor sıçraması maliyeti
    /// kazancı yer (design/01 §3 "flush başına tek sıçrama").
    static let defaultMinimumThreshold = 8 * 1024

    private let lock = NSLock()
    private let defaultThreshold: Int
    private let minimumThreshold: Int
    private var current: Int

    init(
        defaultThreshold: Int,
        minimumThreshold: Int = AdaptiveBatchBudget.defaultMinimumThreshold
    ) {
        let floorValue = min(minimumThreshold, defaultThreshold)
        self.defaultThreshold = defaultThreshold
        self.minimumThreshold = floorValue
        self.current = defaultThreshold
    }

    var threshold: Int {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// Feed bütçeyi aştı: eşiği yarıya indir (alt sınırda dur).
    func noteOverrun() {
        lock.lock()
        current = max(minimumThreshold, current / 2)
        lock.unlock()
    }

    /// Feed bütçe içinde kaldı: kademeli geri açılış (default'u aşma).
    func noteWithinBudget() {
        lock.lock()
        if current < defaultThreshold {
            current = min(defaultThreshold, current * 2)
        }
        lock.unlock()
    }
}
