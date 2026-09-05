import SwiftUI

/// Bilgilendirme kartı: soluk accent zemin + accent kenarlık + info ikonu
/// (Faz 7.2 — `SettingsView.infoCard` yerine).
struct InfoCard: View {
    let text: String
    var icon = "info.circle"

    init(_ text: String, icon: String = "info.circle") {
        self.text = text
        self.icon = icon
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.accentPrimary)
                .padding(.top, Theme.Spacing.xxxs)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentVivid.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.accentVivid.opacity(0.15), lineWidth: Theme.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}

#if DEBUG
#Preview("InfoCard") {
    InfoCard(
        "Notifications only appear when system permission is granted. "
            + "The interval repeats as long as the terminal stays waiting."
    )
    .padding(Theme.Spacing.xxl)
    .frame(width: 480)
    .background(Theme.bgSurface)
}
#endif
