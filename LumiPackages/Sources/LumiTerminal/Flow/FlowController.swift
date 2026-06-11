import Foundation

/// Ack tabanlı uçtan uca flow control sayacı (spec/00 §4.1-2, design/01 §3).
/// In-flight = fd'den okunmuş ama henüz emülatöre feed edilmemiş byte'lar.
/// io queue'dan (produce) ve MainActor'dan (consume) dokunulur; lock korumalı.
public final class FlowController: @unchecked Sendable {
    public enum ProduceDirective: Equatable {
        case proceed
        case suspend
    }

    public static let defaultHighWatermark = 512 * 1024
    public static let defaultLowWatermark = 128 * 1024

    private let lock = NSLock()
    private let highWatermark: Int
    private let lowWatermark: Int
    private var inFlightBytes = 0
    private var suspended = false

    public init(
        highWatermark: Int = FlowController.defaultHighWatermark,
        lowWatermark: Int = FlowController.defaultLowWatermark
    ) {
        precondition(lowWatermark < highWatermark, "low watermark must be below high watermark")
        self.highWatermark = highWatermark
        self.lowWatermark = lowWatermark
    }

    public func noteProduced(_ bytes: Int) -> ProduceDirective {
        lock.lock()
        defer { lock.unlock() }
        inFlightBytes += bytes
        if inFlightBytes >= highWatermark {
            suspended = true
        }
        return suspended ? .suspend : .proceed
    }

    /// Dönüş `true` ise okuma kaldığı yerden sürdürülmelidir (low watermark altına inildi).
    @discardableResult
    public func noteConsumed(_ bytes: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        inFlightBytes = max(0, inFlightBytes - bytes)
        if suspended && inFlightBytes <= lowWatermark {
            suspended = false
            return true
        }
        return false
    }

    public var inFlight: Int {
        lock.lock()
        defer { lock.unlock() }
        return inFlightBytes
    }
}
