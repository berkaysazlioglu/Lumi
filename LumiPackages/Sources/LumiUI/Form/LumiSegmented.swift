import SwiftUI

/// Segmented seçim grubu (v1 `.settings-theme-btn` grubu): pasif bgDeep, aktif
/// accent kenarlık + accent metin + soluk accent zemin; disabled %40 soluk.
struct LumiSegmented<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        var isEnabled = true
        var id: String { label }
    }

    let options: [Option]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func segment(_ option: Option) -> some View {
        let isActive = selection == option.value
        return Button {
            if option.isEnabled { selection = option.value }
        } label: {
            Text(option.label)
                .font(Theme.Typography.bodyMono)
                .foregroundStyle(isActive ? Theme.accentPrimary : Theme.textSecondary)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.md)
                .background(isActive ? Theme.accentVivid.opacity(0.1) : Theme.bgDeep)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(
                            isActive ? Theme.accentVivid : Theme.border,
                            lineWidth: Theme.Stroke.hairline
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!option.isEnabled)
        .opacity(option.isEnabled ? 1 : 0.4)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

#if DEBUG
#Preview("LumiSegmented") {
    LumiSegmented(
        options: [
            .init(value: "auto", label: "Auto"),
            .init(value: "fit", label: "Fit"),
            .init(value: "scroll", label: "Scroll", isEnabled: false),
        ],
        selection: .constant("auto")
    )
    .padding(Theme.Spacing.xxl)
    .background(Theme.bgSurface)
}
#endif
