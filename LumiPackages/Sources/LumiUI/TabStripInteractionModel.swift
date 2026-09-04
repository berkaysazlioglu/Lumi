import Foundation
import Observation

/// Tab şeridinin SwiftUI çizimi ile AppKit etkileşim katmanı
/// (`TabStripInteractionView`) arasındaki paylaşılan durum.
///
/// SwiftUI tarafı chip frame'lerini (hosting view koordinatı, top-left) yayınlar
/// ve `dragging`/`hoveredTab`'a göre çizer; AppKit tarafı frame'leri okur,
/// mouse'u işler, `dragging`/`hoveredTab`'ı yazar ve seçim/taşıma intent'lerini
/// çağırır. Neden iki katman: hosting view içindeki HER basış (SwiftUI jesti
/// veya platform alt view'ı) pencerenin üst 28px titlebar bölgesinde SwiftUI
/// tarafından pencere sürüklemesine çevrilir (ölçüldü); hosting DIŞINDAKİ bir
/// AppKit kardeş view bundan etkilenmez.
@Observable
@MainActor
public final class TabStripInteractionModel {
    public struct Drag: Equatable, Sendable {
        public let tab: String
        public var translation: CGFloat
        public init(tab: String, translation: CGFloat) {
            self.tab = tab
            self.translation = translation
        }
    }

    /// Bu kadar yatay hareketin altında biten basış tıklama sayılır.
    public static let dragThreshold: CGFloat = 4

    /// Chip frame'leri — hosting view koordinatı (top-left origin), tab yolu → rect.
    public var chipFrames: [String: CGRect] = [:]
    public var dragging: Drag?
    public var hoveredTab: String?

    public init() {}

    /// Chip'in sağ ucundaki kapatma butonu: `.padding(.trailing, 6)` + 18×18
    /// (RepoTabChip ile eşleşir). Bu bölge etkileşim katmanından muaf —
    /// SwiftUI Button'a düşer.
    nonisolated public static func closeButtonRect(in chip: CGRect) -> CGRect {
        CGRect(x: chip.maxX - 6 - 18, y: chip.midY - 9, width: 18, height: 18)
    }

    /// Sürüklenen chip'in merkezi hangi tab'ın üstünde? Şeridin dışına taşarsa
    /// uçtaki tab; kendi üstündeyse / boşlukta nil. Saf — test edilebilir.
    nonisolated public static func dropTarget(
        for tab: String,
        translation: CGFloat,
        frames: [String: CGRect]
    ) -> String? {
        guard let own = frames[tab] else { return nil }
        let centerX = own.midX + translation
        let others = frames.filter { $0.key != tab }.sorted { $0.value.minX < $1.value.minX }
        guard let first = others.first, let last = others.last else { return nil }
        if centerX < own.minX, centerX < first.value.minX { return first.key }
        if centerX > own.maxX, centerX > last.value.maxX { return last.key }
        return others.first { $0.value.minX <= centerX && centerX <= $0.value.maxX }?.key
    }
}
