import Foundation
import LumiKit

/// Terminal grid yerleşim matematiği (spec/20 §13 birebir).
/// Saf fonksiyonlar — SwiftUI'dan bağımsız test edilir.
public enum GridLayoutMath {
    public static let gap: CGFloat = 12
    public static let minCardWidth: CGFloat = 400
    /// auto/columns modları scroll'ludur; satır yüksekliği sabittir.
    public static let scrollingRowHeight: CGFloat = 360

    /// Kolon sayısı: auto → floor((w+gap)/(400+gap)) min 1; columns → N;
    /// rows → ceil(görünür / N) min 1.
    public static func columnCount(
        layout: GridLayout,
        containerWidth: CGFloat,
        visibleCount: Int
    ) -> Int {
        switch layout.mode {
        case .auto:
            guard containerWidth > 0 else { return 1 }
            return max(1, Int((containerWidth + gap) / (minCardWidth + gap)))
        case .columns:
            return max(1, layout.count)
        case .rows:
            return max(1, Int(ceil(Double(visibleCount) / Double(max(1, layout.count)))))
        }
    }

    /// Son satır stretch dağıtımı (auto modda YOK): baseSpan = floor(cols/remainder);
    /// cols % remainder fazlası son satırın SONDAKİ kartlarına +1 olarak verilir.
    /// Örn. 5 kolon, 2 artık kart → span 2 ve span 3.
    static func spans(visibleCount: Int, columns: Int, stretchLastRow: Bool) -> [Int] {
        var spans = [Int](repeating: 1, count: visibleCount)
        guard stretchLastRow, columns > 1, visibleCount > 0 else { return spans }
        let remainder = visibleCount % columns
        guard remainder != 0 else { return spans }
        let baseSpan = columns / remainder
        let extra = columns % remainder
        let lastRowStart = visibleCount - remainder
        for offset in 0..<remainder {
            let bonus = offset >= (remainder - extra) ? 1 : 0
            spans[lastRowStart + offset] = baseSpan + bonus
        }
        return spans
    }

    /// Görünür kart frame'leri (yerleşim sırası soldan sağa, satır satır).
    /// rows modu viewport'a sığar (scroll yok); auto/columns sabit satır
    /// yüksekliğiyle scroll'lanır.
    public static func frames(
        layout: GridLayout,
        container: CGSize,
        visibleCount: Int
    ) -> [CGRect] {
        guard visibleCount > 0, container.width > 0 else { return [] }
        let columns = columnCount(layout: layout, containerWidth: container.width, visibleCount: visibleCount)
        let columnWidth = floor((container.width - CGFloat(columns - 1) * gap) / CGFloat(columns))

        let rowHeight: CGFloat
        switch layout.mode {
        case .rows:
            let rows = max(1, layout.count)
            rowHeight = floor((container.height - CGFloat(rows - 1) * gap) / CGFloat(rows))
        case .auto, .columns:
            rowHeight = scrollingRowHeight
        }

        let spanList = spans(
            visibleCount: visibleCount,
            columns: columns,
            stretchLastRow: layout.mode != .auto
        )

        var result: [CGRect] = []
        result.reserveCapacity(visibleCount)
        var column = 0
        var row = 0
        for index in 0..<visibleCount {
            let span = min(spanList[index], columns)
            if column + span > columns {
                column = 0
                row += 1
            }
            let x = CGFloat(column) * (columnWidth + gap)
            let y = CGFloat(row) * (rowHeight + gap)
            let width = CGFloat(span) * columnWidth + CGFloat(span - 1) * gap
            result.append(CGRect(x: x, y: y, width: width, height: rowHeight))
            column += span
            if column >= columns {
                column = 0
                row += 1
            }
        }
        return result
    }

    public static func contentHeight(frames: [CGRect]) -> CGFloat {
        frames.map(\.maxY).max() ?? 0
    }
}
