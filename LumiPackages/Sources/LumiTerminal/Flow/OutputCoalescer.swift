import Foundation

/// Frame hızında chunk birleştirme (spec/00 §4.1-3, design/01 §3).
/// Görünür terminalde ~16ms, gizlide 100ms aralıkla ya da boyut eşiğinde flush eder.
/// io queue'ya confine edilir; chunk başına maliyet O(chunk)'tır.
final class OutputCoalescer {
    static let defaultVisibleInterval: TimeInterval = 0.016
    static let defaultHiddenInterval: TimeInterval = 0.1
    static let defaultSizeThreshold = 128 * 1024

    var onFlush: ((Data) -> Void)?

    private var buffer = Data()
    private var timerActive = false
    private var isHidden = false
    private let scheduler: OneShotScheduling
    private let visibleInterval: TimeInterval
    private let hiddenInterval: TimeInterval
    private let sizeThreshold: Int

    init(
        scheduler: OneShotScheduling,
        visibleInterval: TimeInterval = OutputCoalescer.defaultVisibleInterval,
        hiddenInterval: TimeInterval = OutputCoalescer.defaultHiddenInterval,
        sizeThreshold: Int = OutputCoalescer.defaultSizeThreshold
    ) {
        self.scheduler = scheduler
        self.visibleInterval = visibleInterval
        self.hiddenInterval = hiddenInterval
        self.sizeThreshold = sizeThreshold
    }

    func ingest(_ data: Data) {
        buffer.append(data)
        if buffer.count >= sizeThreshold {
            flushNow()
            return
        }
        guard !timerActive else { return }
        timerActive = true
        scheduler.schedule(after: isHidden ? hiddenInterval : visibleInterval) { [weak self] in
            self?.fireTimer()
        }
    }

    func flushNow() {
        scheduler.cancel()
        timerActive = false
        flushBuffer()
    }

    /// Gizli terminal politikası (spec/00 §4.1-6): aralık genişler, akış durmaz.
    func setHidden(_ hidden: Bool) {
        isHidden = hidden
    }

    private func fireTimer() {
        timerActive = false
        flushBuffer()
    }

    private func flushBuffer() {
        guard !buffer.isEmpty else { return }
        let out = buffer
        buffer = Data()
        onFlush?(out)
    }
}
