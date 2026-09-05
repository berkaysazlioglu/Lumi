import LumiKit
import LumiState
import SwiftUI

/// `.sessions` panel öğesi (Faz 6.2 — eski `LeftSidebarView`'ın üst bölümü):
/// aktif repo'nun terminalleri.
///
/// Parent closure'ı YOK: bağlamını `@Environment(\.shell)`'den okur, tıklamayı
/// doğrudan `TerminalListStore` intent'ine çevirir.
public struct SessionsPanelItem: View {
    /// Liste kabının üst sınırı (v1 paritesi).
    private static let maxListHeight: CGFloat = 180

    @Shell private var shell

    public init() {}

    public var body: some View {
        if let repoPath = shell.activeRepoPath {
            content(repoPath)
        }
    }

    private func content(_ repoPath: String) -> some View {
        let repoTerminals = shell.terminals.terminals(in: repoPath)
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                title: "Sessions",
                icon: "square.stack.3d.up",
                count: repoTerminals.isEmpty ? nil : .neutral(repoTerminals.count)
            )
            .padding(.bottom, repoTerminals.isEmpty ? Theme.Spacing.xs : Theme.Spacing.md)
            if repoTerminals.isEmpty {
                EmptyStatePlaceholder("No active sessions")
            } else {
                sessionList(repoTerminals)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func sessionList(_ repoTerminals: [TerminalMeta]) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xxs) {
                ForEach(repoTerminals) { meta in
                    SessionRow(
                        meta: meta,
                        isActive: shell.terminals.activeTerminalID == meta.id,
                        isMinimized: shell.terminals.isMinimized(meta.id)
                    ) {
                        // Minimize ise önce restore, sonra odak
                        if shell.terminals.isMinimized(meta.id) {
                            shell.terminals.restoreAndFocus(meta.id)
                        } else {
                            shell.terminals.focus(meta.id)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: Self.maxListHeight)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// v1 .session-item: StatusDot + isim; aktif satır elevated zemin + 2px sol
/// accent çizgisi, minimize 0.5 opacity, hover'da aydınlanır.
struct SessionRow: View {
    let meta: TerminalMeta
    let isActive: Bool
    let isMinimized: Bool
    let onSelect: () -> Void

    var body: some View {
        HoverReader { isHovering in
            Button(action: onSelect) {
                HStack(spacing: Theme.Spacing.md) {
                    Circle()
                        .fill(Theme.statusColor(for: meta.status))
                        .frame(width: Theme.Spacing.md, height: Theme.Spacing.md)
                        .accessibilityHidden(true)
                    Text(meta.displayTitle)
                        .font(Theme.Typography.bodyMono)
                        .foregroundStyle(nameColor(isHovering: isHovering))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(isActive || isHovering ? Theme.bgElevated : Color.clear)
                .overlay(alignment: .leading) {
                    if isActive {
                        Rectangle().fill(Theme.accentPrimary).frame(width: Theme.Spacing.xxs)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .opacity(isMinimized ? 0.5 : 1)
        .accessibilityLabel(meta.displayTitle)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func nameColor(isHovering: Bool) -> Color {
        if isActive { return Theme.accentPrimary }
        return isHovering ? Theme.textPrimary : Theme.textSecondary
    }
}

#if DEBUG
#Preview("SessionsPanelItem") {
    SessionsPanelItem()
        .frame(width: 280)
        .background(Theme.bgSurface)
        .environment(\.shell, ShellContext.preview())
}
#endif
