import CoreGraphics
import LumiKit
import SwiftUI

/// Commit graph'ının ölçü ve renk token'ları (karar 40).
///
/// Ölçüler Orca'nın swimlane SVG'sinden alınır; renkler Lumi paletinden
/// seçilir. `laneColors` sırası `CommitGraph`in palet indeksleriyle BİREBİR
/// eşleşir: indeks 0 checkout edilmiş branch'e ayrılmıştır
/// (`CommitGraph.currentBranchColor`).
public extension Theme {
    enum Graph {
        /// 11pt — iki lane arasındaki yatay adım (Orca `SWIMLANE_WIDTH`).
        public static let laneWidth: CGFloat = 11
        /// 3.5pt — commit düğümü yarıçapı (Orca `CIRCLE_RADIUS`).
        public static let nodeRadius: CGFloat = 3.5
        /// 5pt — lane kayarken kullanılan yumuşatma yarıçapı.
        public static let curveRadius: CGFloat = 5
        /// HEAD halkasının ve merge iç deliğinin düğüm yarıçapına eklediği pay.
        public static let ringInset: CGFloat = 3
        /// 96pt — kayan (marquee) ref rozetinin tavanı (karar 45 eki): rozet
        /// bundan geniş olamaz, uzun ad rozet içinde kayar, yorum yer bulur.
        public static let refBadgeMaxWidth: CGFloat = 96
        /// Rozet marquee'sinin döngü aralığı: metin bir tur attıktan sonra bu
        /// kadar boşluk bırakılır (`MarqueeText.trailingGap`in dar rozet sürümü).
        public static let refBadgeMarqueeGap: CGFloat = 24

        /// 5 basamaklı lane paleti. 0 = checkout edilmiş branch (mor vurgu).
        public static let laneColors: [Color] = [
            Theme.accentPrimary,
            Theme.accentCyan,
            Theme.success,
            Theme.warning,
            Theme.graphPink,
        ]

        /// Palet indeksi → renk; indeks taşarsa başa döner (model ve tema
        /// paleti aynı boyda olmalı, ama UI asla çökmez).
        public static func laneColor(_ index: Int) -> Color {
            guard !laneColors.isEmpty else { return Theme.accentPrimary }
            return laneColors[((index % laneColors.count) + laneColors.count) % laneColors.count]
        }

        /// Kolon genişliği: satırlar arası hizalama için TÜM satırlarda aynı
        /// lane sayısı kullanılır, yoksa mesajlar satır satır kayardı.
        public static func columnWidth(laneCount: Int) -> CGFloat {
            laneWidth * CGFloat(max(laneCount, 1) + 1)
        }
    }

    /// Paletin beşinci lane tonu — yalnız graph'ta kullanılır.
    static let graphPink = Color(hex: 0xF472B6)
}

#if DEBUG
extension Theme.Graph {
    /// Lint/test: model paleti ile tema paleti aynı boyda mı?
    static var paletteMatchesModel: Bool { laneColors.count == CommitGraph.paletteSize }
}
#endif
