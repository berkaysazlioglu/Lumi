import Foundation

/// Fare/trackpad wheel delta'larını terminal scroll adımlarına çeviren saf yardımcılar
/// (DropAwareTerminalView'ın alt-buffer scroll köprüsü için — spec/20 scroll davranışı).
///
/// Trackpad'ler piksel-hassas delta + momentum event seli üretir; event başına sabit
/// adım göndermek aşırı kaydırır. Birikimli çeviri: delta'lar toplanır, her `unit`
/// (hücre yüksekliği) dolduğunda 1 adım üretilir, kalan bir sonraki event'e taşınır.
struct WheelStepAccumulator {
    /// Tek event'te üretilebilecek azami adım (kaçak delta'ya karşı emniyet).
    static let maxStepsPerEvent = 40

    private var accumulated: CGFloat = 0

    /// `delta` piksel (precise) ya da satır (klasik tekerlek) cinsinden; `unit` aynı
    /// birimde 1 adımın eşiği. Pozitif sonuç = yukarı. Yön değişiminde kalan birikim
    /// sıfırlanır — ters yönde gecikme hissi yaratmasın.
    mutating func consume(delta: CGFloat, unit: CGFloat) -> Int {
        guard unit > 0, delta != 0 else { return 0 }
        if (accumulated > 0 && delta < 0) || (accumulated < 0 && delta > 0) {
            accumulated = 0
        }
        accumulated += delta
        let rawSteps = Int(accumulated / unit) // sıfıra doğru kırpar; kalan korunur
        accumulated -= CGFloat(rawSteps) * unit
        return max(-Self.maxStepsPerEvent, min(Self.maxStepsPerEvent, rawSteps))
    }
}

/// View noktası → terminal hücresi eşlemesi (wheel raporunun koordinatı için).
/// Raporun byte'a kodlanması SwiftTerm'e bırakılır: Terminal.encodeButton +
/// sendEvent pazarlıklı mouse protokolüne (SGR/X10/urxvt/UTF8) göre kodlar.
enum MouseWheelGeometry {
    /// View noktasını 1-tabanlı hücreye çevirir; sınırlar içine kıskaçlar.
    /// `isFlipped=false` (AppKit default, SwiftTerm böyle): y aşağıdan yukarı büyür.
    static func gridCell(
        forViewPoint point: CGPoint,
        bounds: CGRect,
        cols: Int,
        rows: Int,
        isFlipped: Bool
    ) -> (col: Int, row: Int) {
        let safeCols = max(1, cols)
        let safeRows = max(1, rows)
        guard bounds.width > 0, bounds.height > 0 else { return (1, 1) }
        let cellWidth = bounds.width / CGFloat(safeCols)
        let cellHeight = bounds.height / CGFloat(safeRows)
        let col = min(safeCols, max(1, Int(point.x / cellWidth) + 1))
        let yFromTop = isFlipped ? point.y : (bounds.height - point.y)
        let row = min(safeRows, max(1, Int(yFromTop / cellHeight) + 1))
        return (col, row)
    }
}
