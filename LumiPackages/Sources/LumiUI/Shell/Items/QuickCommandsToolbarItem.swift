import LumiKit
import SwiftUI

/// Aktif checkout'un hızlı komutları (karar 96 — Orca `Run` split-button
/// paritesi). Üretim bölgesinde grid ayarı + New <Provider>'ın SOLUNDA durur.
///
/// Start App doluysa `▶ Start App | ⌄`: sol yarı arka planda başlatır, chevron
/// diğer komutları ve yönetimi açar. Boşsa tek bir `⚡ Actions ⌄` butonu
/// listeyi açar. Çerçeveli ve dolgusuzdur — birincil CTA (mor New <Provider>)
/// ile yarışmasın.
public struct QuickCommandsToolbarItem: View {
    @Shell private var shell
    @State private var isMenuOpen = false

    public init() {}

    public var body: some View {
        if let target = QuickCommandTarget.active(in: shell) {
            control(target)
                .popover(isPresented: $isMenuOpen, arrowEdge: .bottom) {
                    PopoverMenu(
                        items: QuickCommandMenu.items(target: target, shell: shell),
                        dismiss: { isMenuOpen = false }
                    )
                }
        }
    }

    @ViewBuilder
    private func control(_ target: QuickCommandTarget) -> some View {
        HStack(spacing: 0) {
            if let startApp = QuickCommandMenu.startApp(target: target, shell: shell) {
                Button {
                    QuickCommandMenu.runStartApp(startApp, target: target, shell: shell)
                } label: {
                    label(icon: "play.fill", title: QuickCommandRole.startAppName)
                }
                .buttonStyle(segmentStyle)
                .disabled(target.isMissing)
                .help("Start App in \(target.context.name) (runs in the background)")
                .accessibilityLabel("Start App in \(target.context.name)")

                Rectangle()
                    .fill(Theme.border)
                    .frame(width: Theme.Stroke.hairline, height: Theme.Spacing.lg)
                    .accessibilityHidden(true)

                Button { isMenuOpen.toggle() } label: { chevron }
                    .buttonStyle(segmentStyle)
                    .help("More actions")
                    .accessibilityLabel("More actions")
            } else {
                Button { isMenuOpen.toggle() } label: {
                    HStack(spacing: 0) {
                        label(icon: "bolt", title: "Actions")
                        chevron
                    }
                }
                .buttonStyle(segmentStyle)
                .help("Project actions")
                .accessibilityLabel("Project actions")
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(Theme.border, lineWidth: Theme.Stroke.hairline)
                .allowsHitTesting(false)
        )
    }

    private var segmentStyle: HoverButtonStyle {
        HoverButtonStyle(hoverBackground: Theme.bgElevated, cornerRadius: Theme.Radius.md)
    }

    private func label(icon: String, title: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.Typography.ui(.caption, weight: .semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.Typography.mono(.label, weight: .medium))
                .lineLimit(1)
        }
        .padding(.leading, Theme.Spacing.md)
        .padding(.trailing, Theme.Spacing.sm)
        .frame(height: TopBarMetrics.controlHeight)
        .contentShape(Rectangle())
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(Theme.Typography.ui(.micro, weight: .bold))
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(height: TopBarMetrics.controlHeight)
            .contentShape(Rectangle())
            .accessibilityHidden(true)
    }
}
