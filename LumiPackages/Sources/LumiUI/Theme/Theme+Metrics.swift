import CoreGraphics

/// Köşe yarıçapı ve boşluk ölçekleri (Faz 7.1).
///
/// Önce 9 farklı literal yarıçap vardı (3·4·5·6·7·8·10·11·12·16); dört basamağa
/// indirildi. 1pt'lik sapmalar (3→4, 5→4, 7→6, 10→8) gözle ayırt edilmez ama
/// "hangi köşe hangi bağlama ait" sorusunu tek kaynağa bağlar.
public extension Theme {
    enum Radius {
        /// 4pt — rozet, keycap, chip, minik ikon butonu (eski 3/4/5).
        public static let sm: CGFloat = 4
        /// 6pt — input, buton, satır, açılır menü (eski 6/7); modülün varsayılanı.
        public static let md: CGFloat = 6
        /// 8pt — kart ve liste kabı (eski 8/10).
        public static let lg: CGFloat = 8
        /// 16pt — modal panel.
        public static let panel: CGFloat = 16

        /// Ölçeğin tamamı (lint/test).
        public static let scale: [CGFloat] = [sm, md, lg, panel]
    }

    /// Boşluk ölçeği — 2pt tabanlı.
    enum Spacing {
        /// 1pt — rozet gibi çok sıkı dikey dolgular.
        public static let xxxs: CGFloat = 1
        /// 2pt
        public static let xxs: CGFloat = 2
        /// 4pt
        public static let xs: CGFloat = 4
        /// 6pt
        public static let sm: CGFloat = 6
        /// 8pt
        public static let md: CGFloat = 8
        /// 12pt
        public static let lg: CGFloat = 12
        /// 16pt
        public static let xl: CGFloat = 16
        /// 24pt — form alanları arası / bölüm arası.
        public static let xxl: CGFloat = 24
        /// 32pt — panel iç kenar payı.
        public static let xxxl: CGFloat = 32

        /// Ölçeğin tamamı (lint/test).
        public static let scale: [CGFloat] = [xxxs, xxs, xs, sm, md, lg, xl, xxl, xxxl]
    }

    /// Liste satırı yükseklikleri.
    ///
    /// Explorer satırı önce dolgudan türeyen değişken bir yüksekliğe sahipti;
    /// sabit yükseklik hem tarama ritmini düzeltir hem de klavye ile gezinirken
    /// satırların yerinde durmasını sağlar.
    enum Row {
        /// 22pt — file-tree / arama sonucu satırı (yoğun liste).
        public static let compact: CGFloat = 22
        /// 16pt — satır ikonunun sabit kolon genişliği; adlar aynı x'te hizalanır.
        public static let iconColumn: CGFloat = 16
    }

    /// Çizgi kalınlığı — tüm kenarlıklar ve ayraçlar 1pt (hairline).
    enum Stroke {
        public static let hairline: CGFloat = 1
    }
}
