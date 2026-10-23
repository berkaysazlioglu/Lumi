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

    /// Uçuşun evresi: önce çıktığı yerde büyüyüp bekler, sonra uçar.
    enum Stage: Equatable {
        /// `scale`: büyüme ölçeği (bump), `opacity`: beliriş.
        case launch(scale: Double, opacity: Double)
        /// `t`: yol üzerindeki ham ilerleme (0…1, easing öncesi).
        case travel(t: Double)
    }

    static func stage(elapsed: TimeInterval, launch: TimeInterval, travel: TimeInterval) -> Stage {
        guard elapsed >= launch else {
            let p = max(elapsed, 0) / launch
            return .launch(scale: launchScale(p), opacity: min(1, p / appearRatio))
        }
        return .travel(t: min((elapsed - launch) / travel, 1))
    }

    /// Kalkış ölçeği: `popRatio` içinde sıfırdan taşarak büyür (ease-out-back),
    /// sonra 1'de oturur — bekleme evresinin geri kalanı durgundur.
    static func launchScale(_ p: Double) -> Double {
        let u = min(max(p / popRatio, 0), 1)
        let c3 = overshoot + 1
        return 1 + c3 * pow(u - 1, 3) + overshoot * pow(u - 1, 2)
    }

    /// Yumuşak kalkış ve iniş (cubic ease-in-out).
    static func eased(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return clamped < 0.5
            ? 4 * clamped * clamped * clamped
            : 1 - pow(-2 * clamped + 2, 3) / 2
    }

    /// İnişte sönme çarpanı — inişte hiçbir şey patlamaz.
    static func fade(_ t: Double) -> Double {
        min(1, (1 - t) / fadeOutRatio)
    }

    static let fadeOutRatio = 0.25
    /// Bekleme evresinin büyümeye ayrılan kısmı.
    static let popRatio = 0.55
    static let appearRatio = 0.15
    /// Ease-out-back taşma katsayısı (~%25 taşma).
    static let overshoot = 2.6
}
