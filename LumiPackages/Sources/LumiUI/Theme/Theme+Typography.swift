import SwiftUI

/// Tipografi ölçeği (design/03 §5 — "13px taban, tipografi ölçeği
/// `Theme.Typography`'de"; bağlayıcı).
///
/// Faz 7.1 öncesinde LumiUI'da 17 farklı literal punto vardı; bunlar 12
/// basamaklı bir ölçeğe indirildi (ikinci dalgada markdown başlık merdiveni
/// için `heading` eklendi). Tek kullanımlık ara değerler (10.5 / 11.5 /
/// 12.5) en yakın basamağa **aşağı** yuvarlandı — yuvarlama hiçbir yerde puntoyu
/// BÜYÜTMEZ, böylece sabit genişlikli kaplarda (repo tab'ı, file-tree satırı,
/// 26pt top-bar kontrolleri) kırpılma riski doğmaz.
public extension Theme {
    enum Typography {
        /// Ölçeğin bir basamağı. Değer tipi olduğu için çağrı yerinde
        /// `.body` kısayolu kullanılabilir ve `points` ile ham CGFloat'a
        /// (ör. `TerminalCardHeader.Style`) inilebilir.
        public struct Size: Hashable, Sendable, Comparable {
            public let points: CGFloat

            public init(_ points: CGFloat) { self.points = points }

            public static func < (lhs: Size, rhs: Size) -> Bool {
                lhs.points < rhs.points
            }

            /// 8pt — chevron/xmark gibi minik glyph'ler.
            public static let micro = Size(8)
            /// 9pt — rozet metni (ROOT/REPO, stalled, current).
            public static let tiny = Size(9)
            /// 10pt — ikincil meta satırı, küçük ikon.
            public static let caption = Size(10)
            /// 11pt — bölüm başlığı, ipucu (hint), keycap.
            public static let label = Size(11)
            /// 12pt — gövde metni; modülün en sık puntosu.
            public static let body = Size(12)
            /// 13pt — tasarımın taban puntosu (liste satırı, boş durum).
            public static let base = Size(13)
            /// 15pt — panel içi bölüm başlığı.
            public static let title = Size(15)
            /// 18pt — modal/adım başlığı.
            public static let headline = Size(18)
            /// 20pt — markdown H1 ve büyük durum glyph'i. `headline` (18) ile
            /// `display` (22) arasındaki boşluğu kapatır: iki çağrı yeri de
            /// aradaki basamağa yuvarlansaydı ya başlık merdiveni çökerdi
            /// (H1 = H2) ya da uyarı ikonu gözle fark edilir biçimde küçülürdü.
            public static let heading = Size(20)
            /// 22pt — karşılama ekranı ürün adı.
            public static let display = Size(22)
            /// 34pt — onboarding ürün adı.
            public static let hero = Size(34)
            /// 44pt — onboarding tamamlandı glyph'i.
            public static let splash = Size(44)

            /// Ölçeğin tamamı (lint/test).
            public static let scale: [Size] = [
                .micro, .tiny, .caption, .label, .body,
                .base, .title, .headline, .heading, .display, .hero, .splash,
            ]

            /// Ölçekte `offset` basamak yukarı (+) / aşağı (−); uçlarda kırpılır.
            ///
            /// Türetilmiş puntoların (markdown başlık merdiveni, diff gutter'ı)
            /// eski `fontSize ± n` aritmetiğinin yerini alır: aritmetik ölçeğin
            /// DIŞINA çıkabiliyordu, basamak adımı çıkamaz.
            public func stepped(_ offset: Int) -> Size {
                guard let index = Self.scale.firstIndex(of: self) else { return self }
                let target = min(max(index + offset, 0), Self.scale.count - 1)
                return Self.scale[target]
            }
        }

        // MARK: - Fabrikalar

        /// Monospace (JetBrains Mono görsel kimliği) — metinlerin varsayılanı.
        public static func mono(_ size: Size, weight: Font.Weight = .regular) -> Font {
            .system(size: size.points, weight: weight, design: .monospaced)
        }

        /// Sistem yüzü — SF Symbol glyph'leri ve native kontroller.
        public static func ui(_ size: Size, weight: Font.Weight = .regular) -> Font {
            .system(size: size.points, weight: weight)
        }

        /// Yuvarlak yüz — sayaç rozetleri gibi yumuşak öğeler.
        public static func rounded(_ size: Size, weight: Font.Weight = .regular) -> Font {
            .system(size: size.points, weight: weight, design: .rounded)
        }

        // MARK: - Semantik hazır fontlar

        public static let caption = ui(.caption)
        public static let captionMono = mono(.caption)
        public static let label = ui(.label)
        public static let labelMono = mono(.label)
        public static let body = ui(.body)
        public static let bodyMono = mono(.body)
        public static let baseMono = mono(.base)
        public static let title = ui(.title, weight: .semibold)
        public static let titleMono = mono(.title, weight: .semibold)
    }
}
