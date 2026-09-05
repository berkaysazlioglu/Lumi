import SwiftUI

/// Klavye tuşu görünümü (v1 `.shortcut-kbd`): alt kenardaki 1px çizgi + gölge
/// keycap derinliğini verir. Faz 7.2'de `SettingsComponents`'ten çıkarıldı —
/// Settings dışında da (ipucu/kılavuz metinleri) kullanılabilir.
struct Keycap: View {
    let key: String

    var body: some View {
        Text(key)
            .font(Theme.Typography.labelMono)
            .foregroundStyle(Theme.textSecondary)
            .frame(minWidth: 24, minHeight: 24)
            .padding(.horizontal, Theme.Spacing.sm)
            .background(Theme.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
            )
            .overlay(alignment: .bottom) {
                // border-bottom-width: 2px karşılığı — keycap derinliği
                Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .shadow(color: .black.opacity(0.2), radius: 0, y: 1)
            .accessibilityLabel("Key \(key)")
    }
}

#if DEBUG
#Preview("Keycap") {
    HStack(spacing: Theme.Spacing.xs) {
        Keycap(key: "⌘")
        Keycap(key: "⇧")
        Keycap(key: "T")
    }
    .padding(Theme.Spacing.xxl)
    .background(Theme.bgDeep)
}
#endif
