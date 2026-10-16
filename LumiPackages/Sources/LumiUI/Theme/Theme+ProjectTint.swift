import CoreGraphics
import LumiKit
import SwiftUI

/// Proje kimlik renkleri (karar 120) — tonlar, ara tonlar ve opaklıklar YALNIZ burada.
///
/// Palet Tailwind-400 ailesidir: Lumi'nin koyu mor/lacivert zemininde
/// (bgSurface #12121F, bgElevated #1A1A2E) hepsi ≥ 6,4:1 kontrastla okunur.
/// Mor (renksiz projenin aktif ring'i `accentPrimary`), sarı (dikkat, karar 77)
/// ve kırmızı (hata) bilinçli olarak dışarıdadır — o kanallar durum söyler,
/// proje rengi kimlik söyler.
///
/// Renk atanmış projede kartın BÜTÜN kimliği o renktedir: çerçeve + glow,
/// header zemini, başlık, ikon butonları, alt çizgi, kuyruk sayacı. Renksiz
/// projede hiçbiri değişmez.
public extension Theme {
    enum ProjectTint {
        /// Ham değerler (`Theme.Hex` kalıbı): ara tonlar (`Theme.blend`) ve
        /// kontrast testi hex'e ihtiyaç duyar.
        public enum Hex {
            public static let blue: UInt32 = 0x60A5FA
            public static let teal: UInt32 = 0x2DD4BF
            public static let pink: UInt32 = 0xF472B6
            public static let orange: UInt32 = 0xFB923C
            public static let lime: UInt32 = 0xA3E635
            public static let green: UInt32 = 0x4ADE80
            public static let fuchsia: UInt32 = 0xE879F9
        }

        /// Seçili olmayan kartın çerçevesi (zemine karşı ~2,9–4,4:1;
        /// `Theme.border` 1,35:1). Seçili kartta çerçeve tam opaktır.
        public static let borderOpacity = 0.55
        /// Header zemini: `bgElevated` üstüne tint. Sol çubuk kalkınca kimliği
        /// zemin taşır; %14'te pembe projenin pasif başlığı 4,55:1'e iniyordu,
        /// %12 en düşük 4,69:1 bırakır.
        public static let headerOpacity = 0.12
        /// Pasif başlık: `textSecondary` → proje rengi ara tonu.
        public static let restTitleBlend = 0.6
        /// Seçili başlık: `textPrimary` → proje rengine çekilmiş ton.
        public static let activeTitleBlend = 0.35
        /// İkon butonlarının dinlenme tonu (header zemini üstünde ≥ 3,1:1).
        public static let iconRestOpacity = 0.65
        /// İkon butonu hover zemini.
        public static let iconHoverBackgroundOpacity = 0.15
        /// Header alt çizgisi.
        public static let hairlineOpacity = 0.25
        /// Projects satırındaki ve modaldaki renk noktası.
        public static var dotSize: CGFloat { Theme.Spacing.sm }

        public static func hex(_ color: LumiKit.ProjectColor) -> UInt32 {
            switch color {
            case .blue: return Hex.blue
            case .teal: return Hex.teal
            case .pink: return Hex.pink
            case .orange: return Hex.orange
            case .lime: return Hex.lime
            case .green: return Hex.green
            case .fuchsia: return Hex.fuchsia
            }
        }

        /// Kart başlığı: seçiliyken `textPrimary`'ye yakın, değilken
        /// `textSecondary` ile proje renginin ara tonu. Karar 77 dikkat sarısı
        /// çağıranda bunu ezer.
        public static func titleColor(_ color: LumiKit.ProjectColor, isActive: Bool) -> Color {
            isActive
                ? Theme.blend(Theme.Hex.textPrimary, hex(color), activeTitleBlend)
                : Theme.blend(Theme.Hex.textSecondary, hex(color), restTitleBlend)
        }
    }

    /// Proje rengi → SwiftUI rengi. Görünümler tonu kendileri kurmaz.
    static func projectColor(_ color: LumiKit.ProjectColor) -> Color {
        Color(hex: ProjectTint.hex(color))
    }

    /// Terminal kartı kenarlığı — öncelik kuralı LumiKit'te
    /// (`TerminalBorderEmphasis`), renk eşlemesi burada.
    static func terminalBorderColor(_ emphasis: TerminalBorderEmphasis) -> Color {
        switch emphasis {
        case .active(let color): return color.map(projectColor) ?? accentPrimary
        case .attention: return warning
        case .project(let color): return projectColor(color).opacity(ProjectTint.borderOpacity)
        case .rest: return border
        }
    }

    /// Aktif kartın halesi: proje rengi, renksizse eski mor (`accentVivid`).
    /// Hale yalnız aktif kartın dilidir (karar 77: dikkat hale almaz).
    static func terminalGlowColor(_ emphasis: TerminalBorderEmphasis) -> Color? {
        guard case .active(let color) = emphasis else { return nil }
        return color.map(projectColor) ?? accentVivid
    }
}

/// Header içindeki ikon butonlarının (kuyruk, zoom, minimize, kapat) tonu —
/// Environment'tan iner ki kart `IconButton` çağrılarına parametre geçirmesin.
/// `nil` (varsayılan) = Lumi'nin mor-gri tonları.
struct IconButtonTint: Equatable {
    let rest: Color
    let hover: Color
    let hoverBackground: Color
    /// Dolu vurgu (kuyruk sayacı baloncuğu).
    let fill: Color

    static func project(_ color: ProjectColor) -> IconButtonTint {
        let base = Theme.projectColor(color)
        return IconButtonTint(
            rest: base.opacity(Theme.ProjectTint.iconRestOpacity),
            hover: base,
            hoverBackground: base.opacity(Theme.ProjectTint.iconHoverBackgroundOpacity),
            fill: base
        )
    }
}

private struct IconButtonTintKey: EnvironmentKey {
    static let defaultValue: IconButtonTint? = nil
}

extension EnvironmentValues {
    var iconButtonTint: IconButtonTint? {
        get { self[IconButtonTintKey.self] }
        set { self[IconButtonTintKey.self] = newValue }
    }
}
