import Foundation
import LumiKit

/// Bir terminal view'ındaki bekleyen link jestinin durumu (karar 57).
///
/// Tık, basıldığı anda değil BIRAKILDIĞINDA karara bağlanır: arada fare
/// sürüklendiyse kullanıcı metin seçiyordur, tıkta zaten bir seçim varsa
/// tık o seçimi temizlemek içindir — ikisinde de link yolu iptal edilir.
struct TerminalLinkGestureTracker {
    /// Bu eşiğin üstünde hareket = sürükleme (piksel).
    static let dragThreshold: CGFloat = 4

    private struct Pending {
        /// `nil` → link araması mouseUp'a ertelendi (düz tık yolu).
        let link: String?
        let gesture: TerminalLinkGesture
        let origin: CGPoint
        let hadSelection: Bool
        var moved = false
    }

    private var pending: Pending?

    var activeGesture: TerminalLinkGesture? { pending?.gesture }

    /// Sürükleme eşiği aşıldı mı — bekletilen fare raporları mouseUp'ı
    /// beklemeden serbest bırakılsın diye.
    var isCancelledByDrag: Bool { pending?.moved ?? false }

    mutating func begin(link: String?, gesture: TerminalLinkGesture, origin: CGPoint, hadSelection: Bool) {
        pending = Pending(link: link, gesture: gesture, origin: origin, hadSelection: hadSelection)
    }

    mutating func noteDrag(to point: CGPoint) {
        guard var current = pending, !current.moved else { return }
        let dx = point.x - current.origin.x
        let dy = point.y - current.origin.y
        guard (dx * dx + dy * dy).squareRoot() > Self.dragThreshold else { return }
        current.moved = true
        pending = current
    }

    /// Jesti sonlandırır. `nil` → link yolu iptal (sürükleme / var olan seçim /
    /// bekleyen jest yok); dönen değer varsa eylem işletilmelidir.
    mutating func finish(hasSelection: Bool) -> (link: String?, gesture: TerminalLinkGesture)? {
        defer { pending = nil }
        guard let current = pending, !current.moved, !current.hadSelection, !hasSelection else { return nil }
        return (current.link, current.gesture)
    }

    mutating func cancel() {
        pending = nil
    }
}
