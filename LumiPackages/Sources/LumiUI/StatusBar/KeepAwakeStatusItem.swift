import LumiKit
import SwiftUI

/// Alt bar "Keep computer awake" segmenti (karar 43; Orca
/// `CaffeinateStatusSegment`): kahve ikonu + mod etiketi + durum noktası;
/// tıklama üstte mod menüsünü açar (On / Agent / Off, açıklamalı radyo satırları).
public struct KeepAwakeStatusItem: View {
    @Shell private var shell
    @State private var isMenuOpen = false

    private var status: ComputerAwakeStatus { shell.computerAwake.status }

    public init() {}

    public var body: some View {
        Button { isMenuOpen.toggle() } label: {
            StatusBarSegmentLabel {
                Image(systemName: "cup.and.saucer")
                    .font(Theme.Typography.ui(.label))
                    .foregroundStyle(status.isActive ? Theme.textPrimary : Theme.textMuted)
                    .accessibilityHidden(true)
                Text(status.mode.label)
                StatusBarDot(isOn: status.isActive)
            }
        }
        .buttonStyle(StatusBarSegmentStyle())
        .help("\(ComputerAwakeMode.title), \(status.text)")
        .accessibilityLabel("\(ComputerAwakeMode.title), \(status.text)")
        .popover(isPresented: $isMenuOpen, arrowEdge: .top) {
            KeepAwakeMenu(status: status) { mode in
                shell.computerAwake.setMode(mode)
                isMenuOpen = false
            }
        }
    }
}

/// Mod menüsü: başlık satırı (ad + "Agent · Active"), ayraç, üç radyo satırı.
struct KeepAwakeMenu: View {
    let status: ComputerAwakeStatus
    let onSelect: (ComputerAwakeMode) -> Void

    static let width: CGFloat = 256

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
            HStack(spacing: Theme.Spacing.md) {
                Text(ComputerAwakeMode.title)
                    .font(Theme.Typography.ui(.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Text(status.text)
                    .font(Theme.Typography.ui(.caption))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
                .padding(.vertical, Theme.Spacing.xs)
            ForEach(ComputerAwakeMode.allCases, id: \.self) { mode in
                row(mode)
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(width: Self.width)
        .background(Theme.bgElevated)
    }

    private func row(_ mode: ComputerAwakeMode) -> some View {
        let isSelected = mode == status.mode
        return Button { onSelect(mode) } label: {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .font(Theme.Typography.ui(.caption))
                    .foregroundStyle(isSelected ? Theme.accentPrimary : Theme.textMuted)
                    .frame(width: Theme.Row.iconColumn)
                    .padding(.top, Theme.Spacing.xxs)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(mode.label)
                        .font(Theme.Typography.ui(.body))
                        .foregroundStyle(Theme.textPrimary)
                    Text(mode.detail)
                        .font(Theme.Typography.ui(.label))
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(
            HoverButtonStyle(
                foreground: Theme.textPrimary, hoverForeground: Theme.textPrimary,
                background: .clear, hoverBackground: Theme.bgDeep, cornerRadius: Theme.Radius.sm
            )
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(mode.label). \(mode.detail)")
    }
}

#if DEBUG
#Preview("KeepAwakeMenu") {
    KeepAwakeMenu(status: ComputerAwakeStatus(mode: .auto, isActive: true)) { _ in }
        .padding(Theme.Spacing.xxl)
        .background(Theme.bgSurface)
}
#endif
