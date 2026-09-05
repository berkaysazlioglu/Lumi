import SwiftUI

/// Tam genişlikte, eşit bölmeli mod anahtarı (Orca `ToggleGroup` paritesi).
///
/// Native segmented `Picker` panelin koyu zemininde açık gri bir kutu gibi
/// duruyordu; bu anahtar tema token'larıyla çizilir: kap `bgElevated`,
/// seçili bölme `bgDeep` + `textPrimary`, diğerleri `textSecondary`.
/// Explorer (Names/Contents) ve Source Control (Changes/History) paylaşır.
struct SegmentedModeSwitch<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    var help: ((Option) -> String)? = nil
    var accessibilityLabel = "Mode"

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(options, id: \.self) { option in
                segment(option)
            }
        }
        .padding(Theme.Spacing.xxs)
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func segment(_ option: Option) -> some View {
        let isActive = selection == option
        return Button { selection = option } label: {
            Text(title(option))
                .font(Theme.Typography.ui(.label, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xs)
                .background(isActive ? Theme.bgDeep : .clear)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help?(option) ?? title(option))
        .accessibilityLabel(help?(option) ?? title(option))
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

#if DEBUG
#Preview("SegmentedModeSwitch") {
    SegmentedModeSwitch(
        options: ["Names", "Contents"],
        selection: .constant("Contents"),
        title: { $0 }
    )
    .frame(width: 280)
    .padding(Theme.Spacing.xxl)
    .background(Theme.bgSurface)
}
#endif
