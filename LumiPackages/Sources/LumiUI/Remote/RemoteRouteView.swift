import LumiKit
import LumiState
import SwiftUI

/// Remote route'unun sağ tarafında gösterilen sayfa (karar 143).
enum RemotePage: Hashable {
    /// Telefon eşleştirmesi (Settings ▸ Remote ile aynı görünüm).
    case mobile
    /// Mac'ten Mac'e ağ + bu Mac'in hub olarak paylaşılması.
    case thisMac
    /// Seçili uzak terminalin aynası.
    case terminal
}

/// Remote route'u (karar 55'in yer tutucusu; docs/design/08): solda daraltılabilir
/// sidebar (`Mobile`, `This Mac`, hub'lar ve terminalleri), sağda seçili sayfa.
public struct RemoteRouteView: View {
    let remote: RemoteStore
    let controller: RemoteControllerStore
    let mirrors: any RemoteTerminalMirrorMaking

    @State private var page: RemotePage = .thisMac
    @State private var isCollapsed = false

    public init(remote: RemoteStore, controller: RemoteControllerStore, mirrors: any RemoteTerminalMirrorMaking) {
        self.remote = remote
        self.controller = controller
        self.mirrors = mirrors
    }

    public var body: some View {
        HStack(spacing: 0) {
            RemoteSidebar(remote: remote, controller: controller, page: $page, isCollapsed: $isCollapsed)
            Rectangle()
                .fill(Theme.border)
                .frame(width: Theme.Stroke.hairline)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bgDeep)
        .onAppear { if controller.selectedSession != nil { page = .terminal } }
        .onChange(of: controller.selectedSession) { _, selected in
            if selected != nil { page = .terminal }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch page {
        case .mobile:
            RemotePageScroll {
                LumiSectionTitle(
                    title: "Mobile",
                    description: "Telefondan bağlan: QR'ı Lumi mobil uygulamasında okut. Aynı ayarlar Settings ▸ Remote'ta da var.")
                RemoteMobilePane(remote: remote)
            }
        case .thisMac:
            RemotePageScroll {
                LumiSectionTitle(
                    title: "This Mac",
                    description: "Bu Mac'i aynı ağdaki diğer Mac'lerle paylaş ya da onların terminallerine bağlan.")
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    RemoteNetworkSection(remote: remote)
                    if remote.hasNetwork { RemoteThisMacSection(remote: remote) }
                }
            }
        case .terminal:
            if let ref = controller.selectedSession {
                RemoteSessionPane(ref: ref, controller: controller, mirrors: mirrors)
                    .id(ref)
            } else {
                EmptyStatePlaceholder(placeholderText, density: .full)
            }
        }
    }

    private var placeholderText: String {
        if !remote.hasNetwork { return "Create or join a network in This Mac to see other Macs." }
        if controller.hubs.isEmpty { return "No other Mac is sharing on this network yet." }
        return "Pick a terminal on a hub to mirror it here."
    }
}

/// Sağ taraftaki ayar sayfalarının ortak kaydırma + okunabilir genişlik kabı.
private struct RemotePageScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                content()
            }
            .frame(maxWidth: Self.readableWidth, alignment: .leading)
            .padding(Theme.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static var readableWidth: CGFloat { Theme.scaled(560) }
}

/// Uzak terminalin başlığı + gövdesi: Claude terminalinde chat (varsayılan) ya da ayna,
/// diğerlerinde ayna (karar 143 ek).
struct RemoteSessionPane: View {
    let ref: RemoteSessionRef
    let controller: RemoteControllerStore
    let mirrors: any RemoteTerminalMirrorMaking

    @Shell private var shell
    /// Arttıkça ayna aboneliği yeniden kurulur (hub tarafında terminal yeniden boyutlandıysa taze snapshot).
    @State private var reloadToken = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
            if let error = controller.lastError {
                errorBanner(error)
            }
            ZStack {
                switch mode {
                case .chat:
                    RemoteChatView(chat: controller.chatSession(ref), style: RemoteChatStyle(family: fontFamily))
                case .terminal:
                    RemoteMirrorBody(ref: ref, controller: controller, mirrors: mirrors, fontFamily: fontFamily)
                        .id(reloadToken)
                }
                if controller.linkState(ref.hubId) != .connected {
                    EmptyStatePlaceholder(linkText, density: .full)
                        .background(Theme.bgDeep.opacity(Self.overlayOpacity))
                }
            }
        }
    }

    private var session: RemoteSessionInfo? {
        controller.snapshots[ref.hubId]?.session(ref.sessionId)
    }

    private var mode: RemoteSessionViewMode { controller.viewMode(ref) }

    private var fontFamily: String { shell.settings.current.terminalFontFamily }

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
            if session?.provider == .claude {
                SegmentedModeSwitch(
                    options: [RemoteSessionViewMode.chat, .terminal],
                    selection: Binding(get: { mode }, set: { controller.setViewMode($0, for: ref) }),
                    title: { $0 == .chat ? "Chat" : "Terminal" },
                    help: { $0 == .chat
                        ? "Claude's conversation, laid out for this window"
                        : "The hub's raw terminal (menus, trust prompts, /model)" },
                    accessibilityLabel: "View")
                    .frame(width: Self.switchWidth)
            }
            if mode == .terminal {
                Button {
                    reloadToken &+= 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reload the mirror")
            }
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
        .frame(height: Theme.Row.control + Theme.Spacing.sm)
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

    private static let overlayOpacity = 0.85
    private static let bannerOpacity = 0.15
    private static var switchWidth: CGFloat { Theme.scaled(150) }
}

/// Ham PTY aynası. Görev iptal edilince (pane kapandı / yeniden yükleme / görünüm değişti)
/// akış biter ve hub'a `unsubscribe` gider.
private struct RemoteMirrorBody: View {
    let ref: RemoteSessionRef
    let controller: RemoteControllerStore
    let mirrors: any RemoteTerminalMirrorMaking
    let fontFamily: String

    @State private var mirror: (any RemoteTerminalMirroring)?

    var body: some View {
        ZStack {
            if let mirror { RemoteMirrorHost(mirror: mirror) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: makeMirror)
        .task { await stream() }
    }

    private func makeMirror() {
        guard mirror == nil else { return }
        let made = mirrors.makeMirror()
        made.setFont(LumiFonts.mono(family: fontFamily, size: Theme.Typography.Size.base.scaledPoints))
        let controller = controller, ref = ref
        made.onInput = { data in controller.sendInput(ref, data: data) }
        made.onPasteImage = { data in controller.pasteImage(ref, rawImage: data) }
        made.onGridRequest = { grid in controller.requestGrid(ref, grid: grid) }
        mirror = made
    }

    private func stream() async {
        makeMirror()
        for await chunk in controller.terminalOutput(ref) {
            mirror?.apply(chunk)
            if chunk.isSnapshot { mirror?.focus() }
        }
    }
}

/// `RemoteTerminalMirroring.view`'ını SwiftUI'ye taşır.
private struct RemoteMirrorHost: NSViewRepresentable {
    let mirror: any RemoteTerminalMirroring

    func makeNSView(context: Context) -> NSView { mirror.view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
