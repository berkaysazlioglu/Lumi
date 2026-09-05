import SwiftUI

/// Bölüm başlığı + açıklaması (v1 `.settings-section`). Faz 7.2'de `Form/`'a
/// taşındı; Settings dışındaki formlar da kullanabilir.
struct LumiSectionTitle: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.titleMono)
                .foregroundStyle(Theme.textPrimary)
            Text(description)
                .font(Theme.Typography.bodyMono)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.bottom, Theme.Spacing.xxl)
    }
}

#if DEBUG
#Preview("LumiSectionTitle") {
    LumiSectionTitle(title: "General", description: "Repo discovery and default AI provider.")
        .padding(Theme.Spacing.xxxl)
        .frame(width: 480)
        .background(Theme.bgSurface)
}
#endif
