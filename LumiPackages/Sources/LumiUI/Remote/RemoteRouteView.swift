import LumiKit
import LumiState
import SwiftUI

/// Remote route'u (karar 55'in yer tutucusu; docs/design/08): solda bu Mac'in
/// ağ/hub ayarları ve ağdaki hub'lar, sağda seçili uzak terminalin aynası.
public struct RemoteRouteView: View {
    let remote: RemoteStore
    let controller: RemoteControllerStore
    let mirrors: any RemoteTerminalMirrorMaking

    public init(remote: RemoteStore, controller: RemoteControllerStore, mirrors: any RemoteTerminalMirrorMaking) {
        self.remote = remote
        self.controller = controller
        self.mirrors = mirrors
    }

    public var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    RemoteNetworkSection(remote: remote)
                    if remote.hasNetwork {
                        RemoteThisMacSection(remote: remote)
                        RemoteHubsSection(controller: controller)
                    }
                }
                .padding(Theme.Spacing.xl)
            }
            .frame(width: Self.sidebarWidth)
            .background(Theme.bgSurface)

            Rectangle()
                .fill(Theme.border)
                .frame(width: Theme.Stroke.hairline)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bgDeep)
    }

    @ViewBuilder
    private var detail: some View {
        if let ref = controller.selectedSession {
            RemoteMirrorPane(ref: ref, controller: controller, mirrors: mirrors)
                .id(ref)
        } else {
            EmptyStatePlaceholder(placeholderText, density: .full)
        }
    }

    private var placeholderText: String {
        if !remote.hasNetwork { return "Create or join a network to see other Macs." }
        if controller.hubs.isEmpty { return "No other Mac is sharing on this network yet." }
        return "Pick a terminal on a hub to mirror it here."
    }

    private static var sidebarWidth: CGFloat { Theme.scaled(320) }
}

/// Uzak terminalin aynası + başlığı.
struct RemoteMirrorPane: View {
    let ref: RemoteSessionRef
    let controller: RemoteControllerStore
    let mirrors: any RemoteTerminalMirrorMaking

    @Shell private var shell
    @State private var mirror: (any RemoteTerminalMirroring)?
    /// Arttıkça abonelik yeniden kurulur (hub tarafında terminal yeniden boyutlandıysa taze snapshot).
    @State private var reloadToken = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
            if let error = controller.lastError {
                errorBanner(error)
            }
            ZStack {
                if let mirror {
                    RemoteMirrorHost(mirror: mirror)
                }
                if controller.linkState(ref.hubId) != .connected {
                    EmptyStatePlaceholder(linkText, density: .full)
                        .background(Theme.bgDeep.opacity(Self.overlayOpacity))
                }
            }
        }
        .onAppear(perform: makeMirror)
        .task(id: reloadToken) { await stream() }
    }

    private var session: RemoteSessionInfo? {
        controller.snapshots[ref.hubId]?.session(ref.sessionId)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            if let session {
                AgentActivityIcon(state: AgentActivityState(
                    status: TerminalStatus(rawValue: session.status) ?? .idle,
                    isAwaitingDecision: session.awaitingDecision))
                TerminalIdentityIcon(provider: session.provider)
            }
            Text(breadcrumb)
                .font(Theme.Typography.mono(.body, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Theme.Spacing.md)
            Button {
                reloadToken &+= 1
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Reload the mirror (use after the terminal was resized on the hub)")
            Button {
                Task { await controller.closeSession(ref) }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close this terminal on the hub")
        }
        .font(Theme.Typography.ui(.label))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: Theme.Row.control)
        .background(Theme.bgSurface)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
            Text(text)
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: Theme.Spacing.md)
            Button("Dismiss") { controller.dismissError() }
                .buttonStyle(.borderless)
                .font(Theme.Typography.labelMono)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.warning.opacity(Self.bannerOpacity))
    }

    private var breadcrumb: String {
        let hub = controller.hub(ref.hubId)?.name ?? "Hub"
        guard let session else { return hub }
        let title = session.title?.isEmpty == false ? session.title! : (session.provider?.rawValue.capitalized ?? "Shell")
        return [hub, session.repoName, title].filter { !$0.isEmpty }.joined(separator: " / ")
    }

    private var linkText: String {
        switch controller.linkState(ref.hubId) {
        case .waitingForHub: "The hub is offline. Reconnecting when it comes back…"
        case .rejected(let reason): RemoteControllerStore.describeRejection(reason)
        case .connecting: "Connecting…"
        case .connected, .disconnected: "Not connected to this hub."
        }
    }

    private func makeMirror() {
        guard mirror == nil else { return }
        let made = mirrors.makeMirror()
        made.setFont(LumiFonts.mono(family: shell.settings.current.terminalFontFamily, size: Theme.Typography.Size.base.scaledPoints))
        let controller = controller, ref = ref
        made.onInput = { data in controller.sendInput(ref, data: data) }
        mirror = made
    }

    /// Ayna parçalarını uygular; görev iptal edilince (pane kapandı / yeniden yükleme)
    /// akış biter ve hub'a `unsubscribe` gider.
    private func stream() async {
        makeMirror()
        for await chunk in controller.terminalOutput(ref) {
            mirror?.apply(chunk)
            if chunk.isSnapshot { mirror?.focus() }
        }
    }

    private static let overlayOpacity = 0.85
    private static let bannerOpacity = 0.15
}

/// `RemoteTerminalMirroring.view`'ını SwiftUI'ye taşır.
private struct RemoteMirrorHost: NSViewRepresentable {
    let mirror: any RemoteTerminalMirroring

    func makeNSView(context: Context) -> NSView { mirror.view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
