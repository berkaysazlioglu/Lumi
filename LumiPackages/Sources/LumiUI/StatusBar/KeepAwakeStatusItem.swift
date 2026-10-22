import LumiKit
import SwiftUI

/// Alt bar "Keep computer awake" segmenti (karar 43; Orca
/// `CaffeinateStatusSegment`): kahve ikonu + mod etiketi + durum noktası;
/// tıklama üstte mod menüsünü açar (On / Agent / Off, açıklamalı radyo satırları)
/// ve altında kapak anahtarı (karar 122; açıkken segmentte laptop ikonu).
public struct KeepAwakeStatusItem: View {
    @Shell private var shell
    @State private var isMenuOpen = false

    private var status: ComputerAwakeStatus { shell.computerAwake.status }
    private var lid: LidAwakeStatus { shell.computerAwake.lidStatus }

    public init() {}

    public var body: some View {
        Button { isMenuOpen.toggle() } label: {
            StatusBarSegmentLabel {
                Image(systemName: "cup.and.saucer")
                    .font(Theme.Typography.ui(.label))
                    .foregroundStyle(status.isActive ? Theme.textPrimary : Theme.textMuted)
                    .accessibilityHidden(true)
                Text(status.mode.label)
                if lid.isOn {
                    Image(systemName: "laptopcomputer")
                        .font(Theme.Typography.ui(.label))
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityHidden(true)
                }
                StatusBarDot(isOn: status.isActive || lid.isOn)
            }
        }
        .buttonStyle(StatusBarSegmentStyle())
        .help(helpText)
        .accessibilityLabel(helpText)
        .popover(isPresented: $isMenuOpen, arrowEdge: .top) {
            KeepAwakeMenu(
                status: status, lid: lid,
                onSelect: { mode in
                    shell.computerAwake.setMode(mode)
                    isMenuOpen = false
                },
                onToggleLid: { isOn in
                    Task { await shell.computerAwake.setLidAwake(isOn) }
                }
            )
            .task { await shell.computerAwake.refreshLidState() }
        }
    }

    private var helpText: String {
        let base = "\(ComputerAwakeMode.title), \(status.text)"
        return lid.isOn ? "\(base), \(LidAwakeStatus.title)" : base
    }
}

/// Mod menüsü: başlık satırı (ad + "Agent · Active"), ayraç, üç radyo satırı,
/// kapak notu, ayraç ve kapak anahtarı (karar 122).
struct KeepAwakeMenu: View {
    let status: ComputerAwakeStatus
    let lid: LidAwakeStatus
    let onSelect: (ComputerAwakeMode) -> Void
    let onToggleLid: (Bool) -> Void

    static var width: CGFloat { Theme.scaled(256) }

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
            Text(LidAwakeStatus.lidNote)
                .font(Theme.Typography.ui(.label))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
                .padding(.vertical, Theme.Spacing.xs)
            lidRow
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

    private var lidRow: some View {
        Button { onToggleLid(!lid.isOn) } label: {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Group {
                    if lid.isPending {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: lid.isOn ? "checkmark.square.fill" : "square")
                            .font(Theme.Typography.ui(.caption))
                            .foregroundStyle(lid.isOn ? Theme.accentPrimary : Theme.textMuted)
                    }
                }
                .frame(width: Theme.Row.iconColumn)
                .padding(.top, Theme.Spacing.xxs)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(LidAwakeStatus.title)
                        .font(Theme.Typography.ui(.body))
                        .foregroundStyle(Theme.textPrimary)
                    Text(LidAwakeStatus.detail)
                        .font(Theme.Typography.ui(.label))
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note = lid.note {
                        lidWarning(note)
                    }
                    if lid.isOnBattery {
                        lidWarning(LidAwakeStatus.batteryWarning)
                    }
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
        .disabled(lid.isPending)
        .accessibilityAddTraits(lid.isOn ? .isSelected : [])
        .accessibilityLabel("\(LidAwakeStatus.title). \(LidAwakeStatus.detail)")
    }

    private func lidWarning(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.ui(.label))
            .foregroundStyle(Theme.warning)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
#Preview("KeepAwakeMenu") {
    KeepAwakeMenu(
        status: ComputerAwakeStatus(mode: .auto, isActive: true),
        lid: LidAwakeStatus(isOn: true, isOwnedByLumi: true, isOnBattery: true),
        onSelect: { _ in }, onToggleLid: { _ in }
    )
        .padding(Theme.Spacing.xxl)
        .background(Theme.bgSurface)
}
#endif
