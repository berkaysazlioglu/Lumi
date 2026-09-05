import SwiftUI

/// Salt-okunur kısayol referansı (tek kaynak: `MainMenuBuilder`).
struct ShortcutsSettingsTab: SettingsTabContent {
    static let tab: SettingsTab = .shortcuts

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LumiSectionTitle(
                title: "Keyboard Shortcuts",
                description: "Application shortcuts. Read-only reference."
            )
            VStack(spacing: Theme.Stroke.hairline) {
                ForEach(ShortcutReference.all) { reference in
                    row(reference)
                }
            }
            // satır araları 1px çizgi (v1 .shortcuts-list)
            .background(Theme.border)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        }
    }

    private func row(_ reference: ShortcutReference) -> some View {
        HStack(spacing: Theme.Spacing.xl) {
            Text(reference.action)
                .font(Theme.Typography.mono(.base, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(Array(reference.combos.enumerated()), id: \.offset) { index, combo in
                    if index > 0 {
                        Text("–")
                            .font(Theme.Typography.labelMono)
                            .foregroundStyle(Theme.textMuted)
                    }
                    HStack(spacing: Theme.Spacing.xxs) {
                        ForEach(Array(combo.enumerated()), id: \.offset) { _, key in
                            Keycap(key: key)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        // 10pt: ölçek dışı ara değer (v1 paritesi korunuyor).
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Theme.bgDeep)
    }
}

#if DEBUG
#Preview("Shortcuts") {
    SettingsTabPreview(.shortcuts)
}
#endif
