import SwiftUI

/// Arama alanlarının metin glyph'li seçenek anahtarı — `Aa` büyük/küçük harf,
/// `ab` tam kelime, `.*` regex (VS Code'un klasik üçlüsü; glyph'ler ikonlardan
/// daha tanıdık). Explorer içerik araması ve terminal araması (karar 144) ortak kullanır.
struct SearchOptionToggle: View {
    private static let activeOpacity = 0.18

    let glyph: String
    let help: String
    @Binding var isOn: Bool
    var underlined = false

    var body: some View {
        Button { isOn.toggle() } label: {
            Text(glyph)
                .font(Theme.Typography.mono(.label, weight: .semibold))
                .underline(underlined)
                .foregroundStyle(isOn ? Theme.accentPrimary : Theme.textMuted)
                .frame(width: Theme.Spacing.xxl - Theme.Spacing.xxs, height: Theme.Spacing.xxl - Theme.Spacing.xs)
                .background(isOn ? Theme.accentPrimary.opacity(Self.activeOpacity) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
