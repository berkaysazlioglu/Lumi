import AppKit

/// Terminal view'ının hücre geometrisini host'una açar. LumiKit'te yaşar ki
/// LumiUI, SwiftTerm'i (ve LumiTerminal'i) import etmeden ölçebilsin — design/00 §2.
@MainActor
public protocol TerminalGridSizing: AnyObject {
    /// Tek hücrenin piksel boyutu (backing ızgarasına snap'li). Host, satır/sütun
    /// sayısını bundan türetir; sorgu view'ın frame'ini DEĞİŞTİRMEZ.
    var cellSize: CGSize { get }
}

/// Terminal view'ını host container'ına oturtan tek yerleşim otoritesi.
///
/// Emülatör satır/sütun sayısını `Int(boyut / hücre)` ile AŞAĞI yuvarlar ve ızgarayı
/// frame'in sol üst köşesine sabitler (`lineOrigin.y = frame.height - lineOffset`).
/// View tam bounds'a oturtulursa artan boşluk — bir satır yüksekliğine kadar, 13pt'de
/// ~16px — tamamen ALTA ve SAĞA düşer: kartın 8px'lik iç boşluğu altta ~24px'e çıkar,
/// üstte 8px kalır ve terminal çerçeveye asimetrik oturur.
///
/// Çözüm: view, ızgaranın fiilen kapladığı alana (hücre boyutunun tam katı) oturtulup
/// host içinde ORTALANIR; artık iki yana eşit paylaştırılır. Hedef frame hücre
/// boyutundan aritmetikle türetildiği için sonuç idempotenttir — her layout'ta
/// çağrılabilir, delta yoksa `false` döner ve gereksiz redraw doğurmaz.
@MainActor
public enum TerminalGridFit {
    /// Frame gerçekten değiştiyse `true` — çağıran redraw kararını buna bağlar.
    @discardableResult
    public static func fit(_ view: NSView, in host: NSView) -> Bool {
        let bounds = host.bounds
        guard !bounds.isEmpty else { return false }
        let target = targetFrame(for: view, in: bounds, host: host)
        guard !view.frame.equalTo(target) else { return false }
        view.frame = target
        return true
    }

    /// Hücre geometrisi bildirmeyen view (test double'ları) tam bounds'a oturur.
    private static func targetFrame(for view: NSView, in bounds: CGRect, host: NSView) -> CGRect {
        guard let sizing = view as? any TerminalGridSizing else { return bounds }
        let cell = sizing.cellSize
        guard cell.width > 0, cell.height > 0 else { return bounds }

        // Tek hücreden dar/alçak host: ızgarayı sıfıra düşürmek emülatörü 0 sütuna
        // resize ederdi; en az bir hücre bırakılır (bu boyutta zaten hiçbir şey görünmez).
        let grid = CGSize(
            width: max(cell.width, (bounds.width / cell.width).rounded(.down) * cell.width),
            height: max(cell.height, (bounds.height / cell.height).rounded(.down) * cell.height)
        )
        return CGRect(
            origin: CGPoint(
                x: bounds.minX + pixelAligned((bounds.width - grid.width) / 2, in: host),
                y: bounds.minY + pixelAligned((bounds.height - grid.height) / 2, in: host)
            ),
            size: grid
        )
    }

    /// Ortalama artığı backing piksel ızgarasına indirilir; yarım piksellik kayma
    /// glyph'leri bulanıklaştırırdı.
    private static func pixelAligned(_ value: CGFloat, in view: NSView) -> CGFloat {
        let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard scale > 0 else { return value.rounded(.down) }
        return (value * scale).rounded(.down) / scale
    }
}
