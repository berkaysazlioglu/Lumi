import SwiftUI

/// Karar 109: GFM tablosunun sütun genişlikleri — HTML `table-layout: auto`
/// paritesi. Alt görünümler satır-öncelikli hücrelerdir (`columnCount` adet
/// sütun). Her sütun içeriğinin doğal genişliğini ister; toplam sığıyorsa
/// tablo içeriğe göre daralır, sığmıyorsa dar sütunlar doğal genişliğinde
/// kalır ve kalan alan geniş sütunlara doğal genişlikleriyle orantılı
/// paylaştırılır (metin orada sarılır). Satır yüksekliği en uzun hücredir;
/// hücreler satır kutusunu doldurur ki zemin/çizgi kesintisiz olsun.
struct MarkdownTableLayout: Layout {
    let columnCount: Int

    struct Cache {
        var widths: [CGFloat] = []
        var rowHeights: [CGFloat] = []
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard columnCount > 0, !subviews.isEmpty else { return .zero }
        let natural = naturalWidths(subviews)
        let widths = MarkdownTableColumns.fit(natural: natural, available: proposal.width)
        let heights = rowHeights(subviews, widths: widths)
        cache = Cache(widths: widths, rowHeights: heights)
        return CGSize(width: widths.reduce(0, +), height: heights.reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        if cache.widths.count != columnCount {
            _ = sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
        }
        var y = bounds.minY
        for (row, height) in cache.rowHeights.enumerated() {
            var x = bounds.minX
            for column in 0..<columnCount {
                let index = row * columnCount + column
                guard index < subviews.count else { break }
                let width = cache.widths[column]
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: width, height: height)
                )
                x += width
            }
            y += height
        }
    }

    private func naturalWidths(_ subviews: Subviews) -> [CGFloat] {
        var widths = Array(repeating: CGFloat.zero, count: columnCount)
        for (index, subview) in subviews.enumerated() {
            let column = index % columnCount
            widths[column] = max(widths[column], subview.sizeThatFits(.unspecified).width)
        }
        return widths
    }

    private func rowHeights(_ subviews: Subviews, widths: [CGFloat]) -> [CGFloat] {
        let rowCount = (subviews.count + columnCount - 1) / columnCount
        return (0..<rowCount).map { row in
            (0..<columnCount).reduce(CGFloat.zero) { tallest, column in
                let index = row * columnCount + column
                guard index < subviews.count else { return tallest }
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: widths[column], height: nil))
                return max(tallest, size.height)
            }
        }
    }
}

/// Sütun genişliği paylaştırmasının saf aritmetiği (birim testten görünür).
enum MarkdownTableColumns {
    static func fit(natural: [CGFloat], available: CGFloat?) -> [CGFloat] {
        let total = natural.reduce(0, +)
        guard let available, available.isFinite, total > available, total > 0 else { return natural }

        // Adil payın altındaki sütunlar doğal genişliğinde sabitlenir; kalan
        // alan, sabitlenen kalmayana dek geniş sütunlar arasında yeniden bölünür.
        var fixed = Set<Int>()
        while true {
            let flexible = natural.indices.filter { !fixed.contains($0) }
            guard !flexible.isEmpty else { return natural }
            let remaining = available - fixed.reduce(0) { $0 + natural[$1] }
            let share = remaining / CGFloat(flexible.count)
            let newlyFixed = flexible.filter { natural[$0] <= share }
            if newlyFixed.isEmpty {
                let flexibleTotal = flexible.reduce(0) { $0 + natural[$1] }
                return natural.indices.map { index in
                    fixed.contains(index) ? natural[index] : max(0, remaining) * natural[index] / flexibleTotal
                }
            }
            fixed.formUnion(newlyFixed)
        }
    }
}
