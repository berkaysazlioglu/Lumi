import LumiKit
import LumiState
import SwiftUI

/// Terminaldeki bir link/path'e tıklayınca tık noktasında açılan eylem
/// popover'ı (karar 57).
///
/// Başlıkta hedefin kendisi (mono, iki satıra kadar), sağında URL'ler için
/// kopyala ve her hedefte Settings ▸ Terminal kısayolu; altında birincil ve
/// (varsa) alternatif eylem, sağlarında doğrudan çalıştıran tuş kombinasyonu.
struct TerminalLinkActionPopover: View {
    let request: TerminalLinkRequest
    let onRun: (TerminalLinkAction) -> Void
    let onCopy: () -> Void
    let onOpenSettings: () -> Void

    /// Sabit genişlik yerleşim hesabını tek değere bağlar.
    static var width: CGFloat { Theme.scaled(288) }

    /// Ölçüm gelmeden önceki ilk kare için kaba yükseklik (başlık + ayraç +
    /// satırlar + dolgu). Gerçek ölçüm gelince yerleşim kendini düzeltir.
    static func estimatedSize(for request: TerminalLinkRequest) -> CGSize {
        let header = Theme.Row.control + Theme.Spacing.md
        let rows = CGFloat(request.actions.count) * (Theme.Row.control + Theme.Spacing.xxs)
        return CGSize(width: width, height: header + rows + Theme.Spacing.md)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            header
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
            ForEach(request.actions) { row($0) }
        }
        .padding(Theme.Spacing.xs)
        .frame(width: Self.width)
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
        )
        .shadow(color: .black.opacity(0.35), radius: Theme.Radius.lg, y: Theme.Spacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Link actions for \(request.destination)")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            Text(request.destination)
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(request.destination)
            if request.isCopyable {
                IconButton(systemName: "doc.on.doc", label: "Copy link", action: onCopy)
            }
            IconButton(
                systemName: "gearshape",
                label: "Terminal link settings",
                action: onOpenSettings
            )
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.xxs)
    }

    private func row(_ action: TerminalLinkAction) -> some View {
        Button { onRun(action) } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Text(action.title)
                    .font(Theme.Typography.ui(.body))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)
                Spacer(minLength: Theme.Spacing.md)
                if !action.shortcutKeys.isEmpty {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(action.shortcutKeys, id: \.self) { Keycap(key: $0) }
                    }
                    .fixedSize()
                    .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(height: Theme.Row.control)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(
            HoverButtonStyle(
                foreground: Theme.textPrimary,
                hoverForeground: Theme.textPrimary,
                background: .clear,
                hoverBackground: Theme.bgDeep,
                cornerRadius: Theme.Radius.sm
            )
        )
        .accessibilityLabel(action.title)
    }
}

#if DEBUG
#Preview("TerminalLinkActionPopover") {
    VStack(spacing: Theme.Spacing.xl) {
        TerminalLinkActionPopover(
            request: TerminalLinkRequest(
                terminalID: TerminalID(),
                target: .workspace(path: "/Users/dev/wkspaces/Github/Lumi"),
                anchor: .zero,
                primary: .init(
                    slot: .primary, title: "Switch workspace",
                    intent: .switchWorkspace(path: "/Users/dev/wkspaces/Github/Lumi")
                ),
                alternate: .init(
                    slot: .alternate, title: "Open in Finder",
                    intent: .revealInFinder(path: "/Users/dev/wkspaces/Github/Lumi")
                )
            ),
            onRun: { _ in }, onCopy: {}, onOpenSettings: {}
        )
        TerminalLinkActionPopover(
            request: TerminalLinkRequest(
                terminalID: TerminalID(),
                target: .url(URL(string: "https://lumi.dev/docs")!),
                anchor: .zero,
                primary: .init(
                    slot: .primary, title: "Open link",
                    intent: .openURL(URL(string: "https://lumi.dev/docs")!)
                ),
                alternate: nil
            ),
            onRun: { _ in }, onCopy: {}, onOpenSettings: {}
        )
    }
    .padding(Theme.Spacing.xxl)
    .background(Theme.bgDeep)
}
#endif
