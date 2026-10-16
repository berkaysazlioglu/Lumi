import SwiftUI

/// Tema uyumlu tek satır metin girdisi: bgDeep zemin, odakta accent kenarlık
/// (v1 `.settings-input`). Faz 7.2'de `Form/`'a taşındı ve git commit mesajı
/// alanı da bunun üzerine bindi (üç kopyadan biri eksildi).
struct LumiTextInput: View {
    @Binding var text: String
    var placeholder = ""
    var width: CGFloat?
    var autofocus = false
    /// Sır alanı (API anahtarı): karakterler maskelenir.
    var isSecure = false
    var onSubmit: (() -> Void)?
    /// Odağı çağıran yönetecekse (karar 120: emoji paleti alanı önce odaklar).
    var focus: FocusState<Bool>.Binding?

    @FocusState private var ownFocus: Bool

    private var focusBinding: FocusState<Bool>.Binding { focus ?? $ownFocus }
    private var isFocused: Bool { focusBinding.wrappedValue }

    var body: some View {
        field
            .textFieldStyle(.plain)
            .font(Theme.Typography.bodyMono)
            .foregroundStyle(Theme.textPrimary)
            .focused(focusBinding)
            .onAppear { if autofocus { focusBinding.wrappedValue = true } }
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

    @ViewBuilder
    private var field: some View {
        if isSecure {
            SecureField(placeholder, text: $text)
        } else {
            TextField(placeholder, text: $text)
        }
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
