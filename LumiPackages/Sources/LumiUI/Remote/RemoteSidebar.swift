import LumiKit
import LumiState
import SwiftUI

/// Remote route'unun sol sütunu (karar 143): daraltma düğmesi, `Mobile` / `This Mac`
/// sekmeleri ve ağdaki hub'lar. Daraltılınca tamamen kapanmaz — yalnız ikonlar
/// (sekmeler, hub'lar, terminallerin durum + kimlik ikonları) kalır.
struct RemoteSidebar: View {
    let remote: RemoteStore
    let controller: RemoteControllerStore
    @Binding var page: RemotePage
    @Binding var isCollapsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: isCollapsed ? .center : .leading, spacing: Theme.Spacing.xs) {
                    RemoteNavRow(icon: "iphone", title: "Mobile", detail: mobileDetail,
                                 isSelected: page == .mobile, isCollapsed: isCollapsed) { page = .mobile }
                    RemoteNavRow(icon: "desktopcomputer", title: "This Mac", detail: thisMacDetail,
                                 isSelected: page == .thisMac, isCollapsed: isCollapsed) { page = .thisMac }
                    if remote.hasServer {
                        Rectangle()
                            .fill(Theme.border)
                            .frame(height: Theme.Stroke.hairline)
                            .padding(.vertical, Theme.Spacing.md)
                        RemoteHubsSection(
                            controller: controller,
                            isCollapsed: isCollapsed,
                            isTerminalPage: page == .terminal,
                            expand: { setCollapsed(false) },
                            showTerminal: { page = .terminal })
                    }
                }
                .padding(.horizontal, isCollapsed ? Theme.Spacing.xs : Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
            }
        }
        .frame(width: isCollapsed ? Self.collapsedWidth : Self.expandedWidth)
        .background(Theme.bgSurface)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if !isCollapsed {
                Text("REMOTE")
                    .font(Theme.Typography.mono(.caption, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                Spacer(minLength: 0)
            }
            Button { setCollapsed(!isCollapsed) } label: {
                Image(systemName: "sidebar.left")
                    .font(Theme.Typography.ui(.body))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: Theme.Row.control, height: Theme.Row.control)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "Expand sidebar" : "Collapse sidebar")
        }
        .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
        .padding(.horizontal, isCollapsed ? 0 : Theme.Spacing.md)
        .frame(height: Theme.Row.control + Theme.Spacing.md)
    }

    private var mobileDetail: String? {
        guard remote.config.enabled else { return "off" }
        return remote.state == .connected ? "connected" : remote.state.rawValue
    }

    private var thisMacDetail: String? {
        guard remote.hasServer else { return "no server" }
        guard remote.config.hubEnabled else { return nil }
        return remote.hubState == .connected ? "sharing" : remote.hubState.rawValue
    }

    private func setCollapsed(_ collapsed: Bool) {
        withAnimation(Theme.Motion.standardEase) { isCollapsed = collapsed }
    }

    static var expandedWidth: CGFloat { Theme.scaled(300) }
    static var collapsedWidth: CGFloat { Theme.scaled(48) }
}

/// Sidebar'ın sekme satırı; daraltılınca yalnız ikon (+ ipucu).
struct RemoteNavRow: View {
    let icon: String
    let title: String
    let detail: String?
    let isSelected: Bool
    let isCollapsed: Bool
    let action: () -> Void

    var body: some View {
        HoverReader { isHovering in
            Button(action: action) {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: icon)
                        .font(Theme.Typography.ui(.body))
                        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                        .frame(width: Theme.Row.iconColumn)
                    if !isCollapsed {
                        Text(title)
                            .font(Theme.Typography.mono(.body, weight: .semibold))
                            .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                        Spacer(minLength: Theme.Spacing.sm)
                        if let detail {
                            Text(detail)
                                .font(Theme.Typography.captionMono)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
                .padding(.horizontal, isCollapsed ? 0 : Theme.Spacing.md)
                .frame(maxWidth: isCollapsed ? nil : .infinity, alignment: .leading)
                .frame(width: isCollapsed ? Theme.Row.control : nil, height: Theme.Row.control)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(isSelected || isHovering ? Theme.bgElevated : Color.clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(detail.map { "\(title) — \($0)" } ?? title)
        }
    }
}
