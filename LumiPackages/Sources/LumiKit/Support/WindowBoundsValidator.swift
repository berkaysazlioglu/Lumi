import Foundation

/// Restore edilen pencere bounds'unun multi-monitör doğrulaması (spec/30):
/// kaydedilmiş konum artık var olmayan bir ekrandaysa default boyuta düşülür.
public enum WindowBoundsValidator {
    public static let minimumVisibleWidth: CGFloat = 100
    public static let minimumVisibleHeight: CGFloat = 80

    /// `screens`: görünür ekran alanları (visibleFrame'ler). Bounds en az bir
    /// ekranla anlamlı kesişiyorsa geçerlidir; aksi halde nil → default.
    public static func validated(_ bounds: WindowBounds, screens: [CGRect]) -> WindowBounds? {
        guard bounds.width >= 200, bounds.height >= 150 else { return nil }
        let rect = CGRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height)
        for screen in screens {
            let intersection = screen.intersection(rect)
            if intersection.width >= minimumVisibleWidth,
               intersection.height >= minimumVisibleHeight {
                return bounds
            }
        }
        return nil
    }
}
