import AppKit
import LumiKit
import SwiftTerm

/// Bir fontun SwiftTerm hücre boyutunu canlı bir emülatöre dokunmadan ölçer (karar 143 ek).
/// SwiftTerm `cellDimension`'ı dışarı açmaz; ölçüm view'ında iki ızgara farkından türetilir
/// (scroller payı farkta düşer).
@MainActor
enum TerminalCellProbe {
    private static let probe = TerminalView(frame: .zero)
    private static var cache: [String: CGSize] = [:]
    static let fontStep: CGFloat = 0.5
    private static let probeSmall = 10
    private static let probeLarge = 20

    static func cellSize(for font: NSFont) -> CGSize {
        let key = "\(font.fontName)@\(font.pointSize)"
        if let cached = cache[key] { return cached }
        probe.font = font
        let terminal = probe.getTerminal()
        // SwiftTerm çok küçük ızgarayı alt sınıra çeker; iki makul ızgaranın farkı ölçülür.
        terminal.resize(cols: Self.probeLarge, rows: Self.probeLarge)
        let large = probe.getOptimalFrameSize().size
        terminal.resize(cols: Self.probeSmall, rows: Self.probeSmall)
        let small = probe.getOptimalFrameSize().size
        let span = CGFloat(Self.probeLarge - Self.probeSmall)
        let cell = CGSize(width: (large.width - small.width) / span, height: (large.height - small.height) / span)
        cache[key] = cell
        return cell
    }

    /// `grid`'i `size`'a sığdıran en büyük font (yarım punto adımlı, `range` içinde).
    static func fittedFont(base: NSFont, grid: TerminalGrid, in size: CGSize, range: ClosedRange<CGFloat>) -> NSFont {
        let baseCell = cellSize(for: base)
        guard baseCell.width > 0, baseCell.height > 0, grid.cols > 0, grid.rows > 0 else { return base }
        let scale = min(size.width / (baseCell.width * CGFloat(grid.cols)),
                        size.height / (baseCell.height * CGFloat(grid.rows)))
        var points = min(max((base.pointSize * scale / fontStep).rounded(.down) * fontStep, range.lowerBound),
                         range.upperBound)
        while points > range.lowerBound {
            let cell = cellSize(for: base.withSize(points))
            if cell.width * CGFloat(grid.cols) <= size.width, cell.height * CGFloat(grid.rows) <= size.height { break }
            points -= fontStep
        }
        return base.withSize(points)
    }

    /// `size`'a `font` ile sığan ızgara (scroller payı `reserved` düşülerek).
    static func grid(for font: NSFont, in size: CGSize, reservedWidth: CGFloat = 0) -> TerminalGrid {
        let cell = cellSize(for: font)
        guard cell.width > 0, cell.height > 0 else { return TerminalGrid(cols: 0, rows: 0) }
        return TerminalGrid(cols: Int((size.width - reservedWidth) / cell.width),
                            rows: Int(size.height / cell.height))
    }
}
