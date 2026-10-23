import CoreGraphics
import Foundation

/// Bir ışık süzmesinin eğimli yolu (karar 126): iki nokta arasında yukarı
/// doğru kavis yapan ikinci dereceden Bézier. Saf aritmetiktir; çizim
/// `OrchestratorFlightOverlay`'dedir.
struct OrchestratorFlightPath: Equatable {
    let start: CGPoint
    let control: CGPoint
    let end: CGPoint

    /// Kavisin yolun uzunluğuna oranı; `variation` (0…1) aynı kaynaktan
    /// kalkan uçuşlar üst üste binmesin diye bunu biraz açar/kapar.
    static let bowRatio: CGFloat = 0.28
    static let variationRatio: CGFloat = 0.35

    init(from start: CGPoint, to end: CGPoint, variation: CGFloat = 0.5, maxBow: CGFloat) {
        self.start = start
        self.end = end
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        guard length > 0 else {
            control = mid
            return
        }
        // Dik birim vektör; kavis hep yukarı (ekranda -y), dik yolda sola.
        var normal = CGPoint(x: -dy / length, y: dx / length)
        if normal.y > 0 || (normal.y == 0 && normal.x > 0) {
            normal = CGPoint(x: -normal.x, y: -normal.y)
        }
        let scale = 1 + (variation - 0.5) * 2 * Self.variationRatio
        let bow = min(length * Self.bowRatio, maxBow) * scale
        control = CGPoint(x: mid.x + normal.x * bow, y: mid.y + normal.y * bow)
    }

    /// `t` (0…1) anındaki nokta.
    func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
            y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
        )
    }

    /// Yumuşak kalkış ve iniş (cubic ease-in-out).
    static func eased(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return clamped < 0.5
            ? 4 * clamped * clamped * clamped
            : 1 - pow(-2 * clamped + 2, 3) / 2
    }

    /// Başta belirip sonda sönme çarpanı — inişte hiçbir şey patlamaz.
    static func fade(_ t: Double) -> Double {
        min(1, t / fadeInRatio) * min(1, (1 - t) / fadeOutRatio)
    }

    static let fadeInRatio = 0.12
    static let fadeOutRatio = 0.25
}
