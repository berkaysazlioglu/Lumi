import SwiftUI

/// Hover durumunu **içeride** tutan kap (Faz 7.2).
///
/// Modülde 40'tan fazla `@State private var isHovering` kopyası vardı; hepsi
/// aynı üç satırı tekrar ediyordu. Hover'ı türev bir görünüm parametresi olarak
/// gören her yer bunun içine girer:
///
/// ```swift
/// HoverReader { isHovering in
///     Text("x").foregroundStyle(isHovering ? Theme.textPrimary : Theme.textMuted)
/// }
/// ```
struct HoverReader<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content

    @State private var isHovering = false

    var body: some View {
        content(isHovering)
            .onHover { isHovering = $0 }
    }
}

/// Hover'da ön plan/zemin değiştiren standart buton stili (Faz 7.2).
///
/// `Button(...) { label }.buttonStyle(HoverButtonStyle(...))` — etiketin
/// kendisi hover'ı bilmez; renk kararı stile aittir. Hover'ı içerik şeklinde
/// kullanması gereken (ör. kapanma butonunu yalnız hover'da gösteren) yerler
/// `HoverReader`'a başvurur.
struct HoverButtonStyle: ButtonStyle {
    var foreground: Color = Theme.textSecondary
    var hoverForeground: Color = Theme.textPrimary
    var background: Color = .clear
    var hoverBackground: Color = Theme.bgElevated
    var cornerRadius: CGFloat = Theme.Radius.md
    /// Basılıyken uygulanan soluklaşma (native `.plain` davranışına yakın).
    var pressedOpacity: Double = 0.7

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(
            configuration: configuration,
            foreground: foreground,
            hoverForeground: hoverForeground,
            background: background,
            hoverBackground: hoverBackground,
            cornerRadius: cornerRadius,
            pressedOpacity: pressedOpacity
        )
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let foreground: Color
        let hoverForeground: Color
        let background: Color
        let hoverBackground: Color
        let cornerRadius: CGFloat
        let pressedOpacity: Double

        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(isHovering ? hoverForeground : foreground)
                .background(isHovering ? hoverBackground : background)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? pressedOpacity : 1)
                .onHover { isHovering = $0 }
        }
    }
}

#if DEBUG
#Preview("HoverButtonStyle") {
    VStack(spacing: Theme.Spacing.lg) {
        Button("Hover me") {}
            .font(Theme.Typography.bodyMono)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .buttonStyle(HoverButtonStyle())
        HoverReader { isHovering in
            Text(isHovering ? "hovering" : "idle")
                .font(Theme.Typography.bodyMono)
                .foregroundStyle(isHovering ? Theme.accentPrimary : Theme.textMuted)
                .padding(Theme.Spacing.md)
        }
    }
    .padding(Theme.Spacing.xxl)
    .background(Theme.bgDeep)
}
#endif
