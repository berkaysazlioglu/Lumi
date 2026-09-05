import SwiftUI

/// Yüzen yüzey kabı: zemin + köşe + 1px kenarlık + gölge (Faz 7.2).
///
/// Üç kopyası vardı (Settings modal paneli, terminal kartı, popover/dropdown
/// gövdeleri) ve her biri kendi köşesini/opaklığını taşıyordu. Farklar tek
/// karara indirildi:
///
/// | Varyant | Zemin | Köşe | Kenarlık | Gölge |
/// |---|---|---|---|---|
/// | `.modal` | `bgSurface` | `panel` (16) | var | siyah, r32 y16 |
/// | `.card` | `bgSurface` | `lg` (8) | var | yok (aktifken `glow`) |
/// | `.floating` | `bgElevated` | `md` (6) | var | yok |
///
/// Yüzeyler **opaktır**: eski 0.92/0.96 yarı-saydamlıkları kaldırıldı, çünkü
/// üç kopyada üç farklı değer taşınıyordu ve koyu temada gözle ayırt
/// edilmiyordu.
struct Panel<Content: View>: View {
    enum Variant {
        case modal
        case card
        case floating
    }

    /// Aktif terminal kartının mor halesi gibi renkli gölgeler.
    struct Glow {
        let color: Color
        let radius: CGFloat

        static func accent(_ color: Color = Theme.accentVivid) -> Glow {
            Glow(color: color.opacity(0.2), radius: 15)
        }
    }

    var variant: Variant = .floating
    /// Varsayılan kenarlık rengini ezmek için (aktif kart accent kenarlık alır).
    var borderColor: Color?
    /// Kenarlık istenmiyorsa `false`.
    var hasBorder = true
    var glow: Glow?
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                if hasBorder {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor ?? Theme.border, lineWidth: Theme.Stroke.hairline)
                }
            }
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowOffsetY)
            .shadow(color: glow?.color ?? .clear, radius: glow?.radius ?? 0)
    }

    private var background: Color {
        switch variant {
        case .modal, .card: return Theme.bgSurface
        case .floating: return Theme.bgElevated
        }
    }

    private var cornerRadius: CGFloat {
        switch variant {
        case .modal: return Theme.Radius.panel
        case .card: return Theme.Radius.lg
        case .floating: return Theme.Radius.md
        }
    }

    private var shadowColor: Color { variant == .modal ? .black.opacity(0.5) : .clear }
    private var shadowRadius: CGFloat { variant == .modal ? 32 : 0 }
    private var shadowOffsetY: CGFloat { variant == .modal ? 16 : 0 }
}

#if DEBUG
#Preview("Panel") {
    VStack(spacing: Theme.Spacing.xxl) {
        Panel(variant: .modal) {
            Text("Modal")
                .font(Theme.Typography.titleMono)
                .foregroundStyle(Theme.textPrimary)
                .padding(Theme.Spacing.xxl)
        }
        Panel(variant: .card, borderColor: Theme.accentPrimary, glow: .accent()) {
            Text("Active card")
                .font(Theme.Typography.bodyMono)
                .foregroundStyle(Theme.textPrimary)
                .padding(Theme.Spacing.xl)
        }
        Panel(variant: .floating) {
            Text("Popover")
                .font(Theme.Typography.bodyMono)
                .foregroundStyle(Theme.textSecondary)
                .padding(Theme.Spacing.lg)
        }
    }
    .padding(Theme.Spacing.xxxl)
    .background(Theme.bgDeep)
}
#endif
