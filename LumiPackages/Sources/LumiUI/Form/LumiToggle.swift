import SwiftUI

/// 40×22 pill toggle (v1 `.settings-toggle`): açıkken accent-vivid zemin +
/// beyaz thumb sağda.
struct LumiToggleSwitch: View {
    @Binding var isOn: Bool
    /// Erişilebilirlik etiketi — satır başlığı verilmediğinde jenerik kalır.
    var label = "Toggle"

    private static let trackWidth: CGFloat = 40
    private static let trackHeight: CGFloat = 22
    private static let thumbSize: CGFloat = 16

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Theme.accentVivid : Theme.bgDeep)
                    .overlay(
                        Capsule().stroke(
                            isOn ? Theme.accentVivid : Theme.border,
                            lineWidth: Theme.Stroke.hairline
                        )
                    )
                    .frame(width: Self.trackWidth, height: Self.trackHeight)
                Circle()
                    .fill(isOn ? Color.white : Theme.textSecondary)
                    .frame(width: Self.thumbSize, height: Self.thumbSize)
                    .padding(.horizontal, Theme.Spacing.xxs)
            }
            .frame(width: Self.trackWidth, height: Self.trackHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.Motion.standardEase, value: isOn)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "on" : "off")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// Solda başlık + ipucu, sağda toggle; açıkken altında ek kontrol
/// (v1 `.settings-toggle-row`).
struct LumiToggleRow<Trailing: View>: View {
    let title: String
    let hint: String
    @Binding var isOn: Bool
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        hint: String,
        isOn: Binding<Bool>,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.hint = hint
        self._isOn = isOn
        self.trailing = trailing
    }

    var body: some View {
        // 10pt: ölçek dışı ara değer (v1 paritesi korunuyor).
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: Theme.Spacing.xl) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(title)
                        .font(Theme.Typography.mono(.body, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(hint)
                        .font(Theme.Typography.labelMono)
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer(minLength: 0)
                LumiToggleSwitch(isOn: $isOn, label: title)
            }
            if isOn {
                trailing()
            }
        }
    }
}

#if DEBUG
#Preview("LumiToggle") {
    VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
        LumiToggleSwitch(isOn: .constant(true), label: "Blink")
        LumiToggleRow(
            title: "Waiting (unseen)",
            hint: "Instant notification + repeat for unseen waiting terminals",
            isOn: .constant(true)
        ) {
            Text("interval control")
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textMuted)
        }
    }
    .padding(Theme.Spacing.xxl)
    .frame(width: 420)
    .background(Theme.bgSurface)
}
#endif
