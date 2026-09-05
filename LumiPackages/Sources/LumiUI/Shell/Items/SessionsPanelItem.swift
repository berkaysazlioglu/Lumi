import LumiKit
import LumiState
import SwiftUI

/// `.sessions` panel öğesi (Faz 6.2 — eski `LeftSidebarView`'ın üst bölümü):
/// aktif repo'nun terminalleri.
///
/// Parent closure'ı YOK: bağlamını `@Environment(\.shell)`'den okur, tıklamayı
/// doğrudan `TerminalListStore` intent'ine çevirir.
public struct SessionsPanelItem: View {
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
            SidebarSectionHeader(
                icon: "square.stack.3d.up",
                title: "Sessions",
                count: repoTerminals.isEmpty ? nil : repoTerminals.count
            )
            .padding(.bottom, repoTerminals.isEmpty ? 4 : 8)
            if repoTerminals.isEmpty {
                Text("No active sessions")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
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
                .frame(maxHeight: 180)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
    }
}

/// v1 .section-header: accent ikon + 11px uppercase başlık + opsiyonel sayaç
/// badge'i + opsiyonel sağ aksiyon.
struct SidebarSectionHeader<Trailing: View>: View {
    let icon: String
    let title: String
    var count: Int?
    @ViewBuilder var trailing: () -> Trailing

    init(
        icon: String,
        title: String,
        count: Int? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.title = title
        self.count = count
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Theme.accentPrimary)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Theme.textSecondary)
            if let count {
                Text("\(count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Spacer(minLength: 0)
            trailing()
        }
    }
}

/// v1 .session-item: StatusDot + isim; aktif satır elevated zemin + 2px sol
/// accent çizgisi, minimize 0.5 opacity, hover'da aydınlanır.
struct SessionRow: View {
    let meta: TerminalMeta
    let isActive: Bool
    let isMinimized: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.statusColor(for: meta.status))
                    .frame(width: 8, height: 8)
                Text(meta.displayTitle)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(nameColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isActive || isHovering ? Theme.bgElevated : Color.clear)
            .overlay(alignment: .leading) {
                if isActive {
                    Rectangle().fill(Theme.accentPrimary).frame(width: 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isMinimized ? 0.5 : 1)
        .onHover { isHovering = $0 }
    }

    private var nameColor: Color {
        if isActive { return Theme.accentPrimary }
        return isHovering ? Theme.textPrimary : Theme.textSecondary
    }
}
