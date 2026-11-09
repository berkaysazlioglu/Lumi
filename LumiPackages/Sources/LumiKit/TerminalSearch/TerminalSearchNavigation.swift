import Foundation

/// Buffer'daki bir eşleşmenin başlangıcı: kaydırmadan bağımsız satır
/// (scrollback'in başından sayılır, kırpılan satırlar dahil) + sütun.
public struct TerminalSearchPosition: Comparable, Hashable, Sendable {
    public let row: Int
    public let col: Int

    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.row, lhs.col) < (rhs.row, rhs.col)
    }
}

/// Etkin eşleşmenin seçimi (karar 144). Saf kural — buffer'ı görmez.
///
/// Orca (xterm `addon-search`) ile aynı: `next`/`previous` sarar, `incremental`
/// etkin eşleşme hâlâ oradaysa yerinde kalır, değilse ondan sonrakine geçer.
/// Tek bilinçli fark etkin eşleşme YOKKEN: xterm scrollback'in en başından
/// başlar; terminalde aranan çoğunlukla az önceki çıktıdır, bu yüzden önce
/// görünür alandaki ilk eşleşme, yoksa görünür alanın üstündeki en yakın
/// (en yeni), o da yoksa altındaki ilk eşleşme seçilir.
public enum TerminalSearchNavigation {
    /// - Parameters:
    ///   - positions: Artan sırada eşleşme başlangıçları.
    ///   - active: Şu an etkin eşleşmenin başlangıcı (yeniden taramadan önceki).
    ///   - visibleRows: Görünür alanın kaydırmadan bağımsız satır aralığı.
    /// - Returns: Yeni etkin eşleşmenin indeksi; eşleşme yoksa `nil`.
    public static func select(
        _ step: TerminalSearchStep,
        positions: [TerminalSearchPosition],
        active: TerminalSearchPosition?,
        visibleRows: ClosedRange<Int>
    ) -> Int? {
        guard !positions.isEmpty else { return nil }
        guard let active else { return nearestToViewport(positions, visibleRows: visibleRows) }
        switch step {
        case .incremental:
            return positions.firstIndex { $0 >= active } ?? nearestToViewport(positions, visibleRows: visibleRows)
        case .next:
            return positions.firstIndex { $0 > active } ?? 0
        case .previous:
            return positions.lastIndex { $0 < active } ?? positions.count - 1
        }
    }

    static func nearestToViewport(_ positions: [TerminalSearchPosition], visibleRows: ClosedRange<Int>) -> Int {
        if let visible = positions.firstIndex(where: { visibleRows.contains($0.row) }) { return visible }
        if let above = positions.lastIndex(where: { $0.row < visibleRows.lowerBound }) { return above }
        return 0
    }
}
