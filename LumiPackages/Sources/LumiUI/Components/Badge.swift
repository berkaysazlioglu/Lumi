import SwiftUI

/// Küçük etiket rozeti (Faz 7.2).
///
/// Modülde beş ayrı kopya vardı: git "current" rozeti, CHANGES sayacı,
/// Sessions sayacı, Settings'teki ROOT/REPO tipi ve terminal "stalled"
/// uyarısı. Hepsi aynı şeyin varyasyonuydu — punto, dolgu ve köşe ölçüleri
/// artık tek yerde.
struct Badge: View {
    /// Zemin ailesi.
    enum Style {
        /// Rengin soluk hâli zemin, rengin kendisi metin (durum rozetleri).
        case tinted
        /// Nötr elevated zemin + muted metin (sayaçlar).
        case neutral
    }

    /// Dış hat.
    enum Shape {
        case rounded
        case capsule
    }

    let text: String
    var color: Color = Theme.accentPrimary
    var size: Theme.Typography.Size = .tiny
    var weight: Font.Weight = .semibold
    var style: Style = .tinted
    var shape: Shape = .rounded

    var body: some View {
        Text(text)
            .font(Theme.Typography.mono(size, weight: weight))
            .foregroundStyle(style == .tinted ? color : Theme.textMuted)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xxxs)
            .background(background)
            .clipShape(clipShape)
    }

    private var background: Color {
        switch style {
        case .tinted: return color.opacity(0.2)
        case .neutral: return Theme.bgElevated
        }
    }

    private var clipShape: AnyShape {
        switch shape {
        case .rounded: return AnyShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        case .capsule: return AnyShape(Capsule())
        }
    }
}

#if DEBUG
#Preview("Badge") {
    HStack(spacing: Theme.Spacing.md) {
        Badge(text: "current")
        Badge(text: "ROOT", color: Theme.accentCyan)
        Badge(text: "stalled", color: Theme.warning)
        Badge(text: "3", color: Theme.warning, size: .caption, weight: .bold, shape: .capsule)
        Badge(text: "7", size: .label, weight: .regular, style: .neutral)
    }
    .padding(Theme.Spacing.xxl)
    .background(Theme.bgSurface)
}
#endif
