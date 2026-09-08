import SwiftUI

/// Tema uyumlu tek satır metin girdisi: bgDeep zemin, odakta accent kenarlık
/// (v1 `.settings-input`). Faz 7.2'de `Form/`'a taşındı ve git commit mesajı
/// alanı da bunun üzerine bindi (üç kopyadan biri eksildi).
struct LumiTextInput: View {
    @Binding var text: String
    var placeholder = ""
    var width: CGFloat?
    var autofocus = false
    var onSubmit: (() -> Void)?

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(Theme.Typography.bodyMono)
            .foregroundStyle(Theme.textPrimary)
            .focused($isFocused)
            .onAppear { if autofocus { isFocused = true } }
            .onSubmit { onSubmit?() }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .background(Theme.bgDeep)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(
                        isFocused ? Theme.accentVivid : Theme.border,
                        lineWidth: Theme.Stroke.hairline
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}

#if DEBUG
#Preview("LumiTextInput") {
    VStack(spacing: Theme.Spacing.lg) {
        LumiTextInput(text: .constant("hello"), placeholder: "Prompt")
        LumiTextInput(text: .constant(""), placeholder: "Commit message…")
    }
    .padding(Theme.Spacing.xxl)
    .frame(width: 360)
    .background(Theme.bgSurface)
}
#endif
