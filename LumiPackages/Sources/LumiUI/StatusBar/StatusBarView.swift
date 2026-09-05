import LumiKit
import SwiftUI

/// Alt bar ölçüleri (karar 43; Orca `StatusBar`: `h-6 px-3 gap-4`).
/// Punto/radius burada yoktur — onlar `Theme` token'larından gelir.
public enum StatusBarMetrics {
    /// Bar yüksekliği (Orca 24px).
    public static let height: CGFloat = 24
    /// Segment ve ikon buton yüksekliği.
    public static let controlHeight: CGFloat = 18
    /// Yatay iç boşluk (Orca `px-3`).
    public static let horizontalPadding: CGFloat = 12
    /// Durum noktası çapı (Orca `size-1.5`).
    public static let dotSize: CGFloat = 6
    /// Popover genişliği (Orca `w-[26rem]`).
    public static let popoverWidth: CGFloat = 416
    /// Resource Manager liste gövdesinin sabit yüksekliği — polling
    /// sırasında popover'ın zıplamaması için (Orca `h-[420px]`).
    public static let popoverBodyHeight: CGFloat = 360
}

/// Pencerenin en altındaki ince durum barı (karar 43; Orca `StatusBar`).
///
/// `HeaderBarView` gibi hiçbir kontrolün adını bilmez: sol grup
/// `.statusLeading`, sağ grup `.statusTrailing` bölgesinden çözülür.
struct StatusBarView: View {
    let registry: ToolbarRegistry

    @Shell private var shell

    var body: some View {
        HStack(spacing: 0) {
            region(.statusLeading)
            Spacer(minLength: Theme.Spacing.lg)
            region(.statusTrailing)
        }
        .padding(.horizontal, StatusBarMetrics.horizontalPadding)
        .frame(height: StatusBarMetrics.height)
        .frame(maxWidth: .infinity)
        .background(Theme.bgSurface)
        .overlay(alignment: .top) {
            Theme.border.frame(height: Theme.Stroke.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status bar")
    }

    private func region(_ region: ToolbarRegion) -> some View {
        HStack(spacing: region.spacing) {
            ForEach(registry.items(in: region, context: shell)) { item in
                item.makeView()
            }
        }
    }
}

/// Alt bar segment butonu: ikon + kısa metin, hover'da hafif zemin
/// (Orca `rounded px-1 py-0.5 hover:bg-accent/70`).
struct StatusBarSegmentStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverButtonStyle(
            foreground: Theme.textMuted,
            hoverForeground: Theme.textPrimary,
            background: .clear,
            hoverBackground: Theme.bgElevated,
            cornerRadius: Theme.Radius.sm
        )
        .makeBody(configuration: configuration)
    }
}

/// Segment içeriği için ortak çerçeve: sabit yükseklik + yatay pay.
struct StatusBarSegmentLabel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) { content() }
            .font(Theme.Typography.ui(.label, weight: .medium))
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(height: StatusBarMetrics.controlHeight)
            .contentShape(Rectangle())
    }
}

/// Segmentlerdeki küçük durum noktası.
struct StatusBarDot: View {
    let isOn: Bool

    var body: some View {
        Circle()
            .fill(isOn ? Theme.textPrimary : Theme.textMuted.opacity(Self.offOpacity))
            .frame(width: StatusBarMetrics.dotSize, height: StatusBarMetrics.dotSize)
            .accessibilityHidden(true)
    }

    private static let offOpacity = 0.4
}

#if DEBUG
#Preview("StatusBarView") {
    var registry = ToolbarRegistry()
    registry.register(ToolbarItemDescriptor(
        id: .settings, region: .statusLeading, order: 0,
        makeView: { AnyView(SettingsToolbarItem()) }
    ))
    registry.register(ToolbarItemDescriptor(
        id: .keepAwake, region: .statusTrailing, order: 0,
        makeView: { AnyView(KeepAwakeStatusItem()) }
    ))
    registry.register(ToolbarItemDescriptor(
        id: .resourceManager, region: .statusTrailing, order: 10,
        makeView: { AnyView(ResourceManagerStatusItem()) }
    ))
    return StatusBarView(registry: registry)
        .frame(width: 640)
        .environment(\.shell, ShellContext.preview())
}
#endif
