import SwiftUI

/// Form alanı: başlık + ipucu + kontrol; alt ayraç son alanda gizlenir
/// (v1 `.settings-field`).
///
/// Faz 7.2'de `SettingsComponents`'ten `Form/`'a taşındı ve adı `Settings`
/// önekinden kurtuldu — "yalnız Settings kullanır" kısıtı kalktı.
struct LumiField<Content: View>: View {
    let title: String
    let hint: String?
    var isLast = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Theme.Typography.mono(.body, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, hint == nil ? Theme.Spacing.md : Theme.Spacing.xxs)
            if let hint {
                Text(hint)
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.bottom, Theme.Spacing.md)
            }
            content()
            if !isLast {
                Rectangle()
                    .fill(Theme.border.opacity(0.3))
                    .frame(height: Theme.Stroke.hairline)
                    .padding(.top, Theme.Spacing.xxl)
            }
        }
        .padding(.bottom, isLast ? 0 : Theme.Spacing.xxl)
    }
}

#if DEBUG
#Preview("LumiField") {
    VStack(alignment: .leading, spacing: 0) {
        LumiField(title: "Projects Root", hint: "First-level subdirectories are listed as repos") {
            LumiTextInput(text: .constant("/Users/me/Projects"))
        }
        LumiField(title: "AI Provider", hint: nil, isLast: true) {
            LumiSegmented(
                options: [.init(value: 0, label: "Claude"), .init(value: 1, label: "Codex")],
                selection: .constant(0)
            )
        }
    }
    .padding(Theme.Spacing.xxxl)
    .frame(width: 480)
    .background(Theme.bgSurface)
}
#endif
