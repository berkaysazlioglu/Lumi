import LumiKit
import LumiState
import SwiftUI

/// Ağdaki hub'lar ve bağlı hub'ın `Proje → Checkout → Ajan` ağacı (docs/design/08).
struct RemoteHubsSection: View {
    let controller: RemoteControllerStore
    /// Sidebar daraltılmış: yalnız ikonlar.
    let isCollapsed: Bool
    /// Sağda terminal sayfası açık mı (seçili terminal yalnız o zaman vurgulanır).
    let isTerminalPage: Bool
    /// Daraltılmışken şifre gerekirse sidebar'ı açar.
    let expand: () -> Void
    /// Terminal seçilince sağı terminal sayfasına çevirir.
    let showTerminal: () -> Void

    var body: some View {
        VStack(alignment: isCollapsed ? .center : .leading, spacing: Theme.Spacing.sm) {
            if !isCollapsed {
                RemoteSectionHeader(title: "Hubs", trailing: directoryLabel)
                if controller.hubs.isEmpty {
                    Text(controller.directoryState == .connected
                         ? "No other Mac is sharing on this network."
                         : "Connecting to the relay…")
                        .modifier(RemoteHintStyle())
                }
            }
            ForEach(controller.hubs) { hub in
                RemoteHubRow(hub: hub, controller: controller, isCollapsed: isCollapsed,
                             isTerminalPage: isTerminalPage, expand: expand, showTerminal: showTerminal)
            }
        }
    }

    private var directoryLabel: String? {
        controller.directoryState == .connected ? nil : controller.directoryState.rawValue
    }
}

/// Bir hub: satır, gerekirse şifre formu, bağlıysa ağaç.
private struct RemoteHubRow: View {
    let hub: RemoteHubInfo
    let controller: RemoteControllerStore
    let isCollapsed: Bool
    let isTerminalPage: Bool
    let expand: () -> Void
    let showTerminal: () -> Void

    @State private var isAskingPassword = false
    @State private var passwordDraft = ""
    @State private var remember = true

    private var link: RemoteHubLinkState { controller.linkState(hub.id) }
    private var isExpanded: Bool { controller.selectedHubId == hub.id && link == .connected }

    var body: some View {
        VStack(alignment: isCollapsed ? .center : .leading, spacing: Theme.Spacing.xs) {
            if isCollapsed {
                collapsedRow
            } else {
                row
                if case .rejected(let reason) = link {
                    Text(RemoteControllerStore.describeRejection(reason))
                        .font(Theme.Typography.labelMono)
                        .foregroundStyle(Theme.error)
                }
                if isAskingPassword {
                    passwordForm
                }
            }
            if isExpanded, let snapshot = controller.snapshots[hub.id] {
                if isCollapsed {
                    RemoteCollapsedAgents(hubId: hub.id, snapshot: snapshot, controller: controller,
                                          isTerminalPage: isTerminalPage, showTerminal: showTerminal)
                } else {
                    RemoteHubTree(hubId: hub.id, snapshot: snapshot, controller: controller,
                                  isTerminalPage: isTerminalPage, showTerminal: showTerminal)
                        .padding(.leading, Theme.Spacing.lg)
                }
            }
        }
    }

    /// Daraltılmış sidebar: bilgisayar ikonu + çevrimiçi noktası; ipucunda ad ve durum.
    private var collapsedRow: some View {
        HoverReader { isHovering in
            Image(systemName: "desktopcomputer")
                .font(Theme.Typography.ui(.body))
                .foregroundStyle(hub.isOnline ? Theme.textPrimary : Theme.textMuted)
                .frame(width: Theme.Row.control, height: Theme.Row.control)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(link == .connected ? Theme.success : (hub.isOnline ? Theme.accentCyan : Theme.textMuted))
                        .frame(width: Theme.Spacing.sm, height: Theme.Spacing.sm)
                        .padding(Theme.Spacing.xxs)
                }
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(isHovering || isExpanded ? Theme.bgElevated : Color.clear))
                .contentShape(Rectangle())
                .onTapGesture(perform: activate)
                .help([hub.name, linkLabel].filter { !$0.isEmpty }.joined(separator: " — "))
        }
    }

    private var row: some View {
        HoverReader { isHovering in
            HStack(spacing: Theme.Spacing.md) {
                Circle()
                    .fill(hub.isOnline ? Theme.success : Theme.textMuted)
                    .frame(width: Theme.Spacing.md, height: Theme.Spacing.md)
                Image(systemName: "desktopcomputer")
                    .foregroundStyle(Theme.textSecondary)
                Text(hub.name)
                    .font(Theme.Typography.mono(.body, weight: .semibold))
                    .foregroundStyle(hub.isOnline ? Theme.textPrimary : Theme.textMuted)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                Text(linkLabel)
                    .font(Theme.Typography.captionMono)
                    .foregroundStyle(Theme.textMuted)
                if link == .connected || link == .waitingForHub {
                    Button {
                        controller.disconnect(hubId: hub.id)
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Disconnect from \(hub.name)")
                }
            }
            .font(Theme.Typography.ui(.label))
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Row.control)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(isHovering || isExpanded ? Theme.bgElevated : Color.clear))
            .contentShape(Rectangle())
            .onTapGesture(perform: activate)
        }
    }

    private var passwordForm: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            LumiTextInput(text: $passwordDraft, placeholder: "Password for \(hub.name)", autofocus: true,
                          isSecure: true, onSubmit: connectWithPassword)
            Toggle("Remember password", isOn: $remember)
                .toggleStyle(.checkbox)
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.Spacing.md) {
                LumiActionButton(title: "Connect", kind: .primary, action: connectWithPassword)
                    .disabled(passwordDraft.isEmpty)
                LumiActionButton(title: "Cancel") { isAskingPassword = false; passwordDraft = "" }
            }
        }
        .padding(.leading, Theme.Spacing.lg)
    }

    private var linkLabel: String {
        switch link {
        case .connected: return hub.controllerCount > 1 ? "\(hub.controllerCount) connected" : "connected"
        case .connecting: return "connecting…"
        case .waitingForHub: return "waiting"
        case .rejected: return "refused"
        case .disconnected: return hub.isOnline ? "" : "offline"
        }
    }

    private func activate() {
        switch link {
        case .connected:
            controller.selectedHubId = isExpanded ? nil : hub.id
        case .connecting, .waitingForHub:
            break
        case .disconnected, .rejected:
            guard hub.isOnline else { return }
            Task {
                // Hatırlanan şifre varsa sormadan dene; yoksa (ya da reddedildiyse) sor —
                // daraltılmış sidebar'da form görünmediği için önce açılır.
                if case .disconnected = link, await controller.hasRememberedPassword(hubId: hub.id) {
                    await controller.connect(hubId: hub.id, password: nil, remember: true)
                } else {
                    if isCollapsed { expand() }
                    isAskingPassword = true
                }
            }
        }
    }

    private func connectWithPassword() {
        guard !passwordDraft.isEmpty else { return }
        let password = passwordDraft
        passwordDraft = ""
        isAskingPassword = false
        Task { await controller.connect(hubId: hub.id, password: password, remember: remember) }
    }
}

/// Bağlı hub'ın proje ağacı; checkout'ta `+` ile yeni terminal, ajan satırında ayna.
private struct RemoteHubTree: View {
    let hubId: String
    let snapshot: RemoteHubSnapshot
    let controller: RemoteControllerStore
    let isTerminalPage: Bool
    let showTerminal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            if snapshot.projects.isEmpty && snapshot.others.isEmpty {
                Text("No projects on this hub.").modifier(RemoteHintStyle())
            }
            ForEach(snapshot.projects) { project in
                Text(project.name)
                    .font(Theme.Typography.mono(.label, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, Theme.Spacing.xs)
                ForEach(project.checkouts) { checkout in
                    checkoutRow(checkout)
                    agents(checkout.agentIds)
                }
            }
            ForEach(snapshot.others) { group in
                Text(group.label)
                    .font(Theme.Typography.mono(.label, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.top, Theme.Spacing.xs)
                agents(group.agentIds)
            }
        }
    }

    private func checkoutRow(_ checkout: RemoteCheckoutNode) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: checkout.kind == "root" ? "house" : "arrow.triangle.branch")
                .foregroundStyle(Theme.textMuted)
            Text(checkout.branch.map { "\(checkout.title) · \($0)" } ?? checkout.title)
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Theme.Spacing.sm)
            Menu {
                Button("New Claude") { start(checkout, .claude(model: nil)) }
                ForEach(ClaudeModelAlias.allCases, id: \.self) { model in
                    Button("New Claude · \(model.displayName)") { start(checkout, .claude(model: model)) }
                }
                Divider()
                Button("New Bash") { start(checkout, .shell) }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Open a terminal on the hub")
        }
        .font(Theme.Typography.ui(.label))
        .padding(.leading, Theme.Spacing.sm)
    }

    @ViewBuilder
    private func agents(_ ids: [String]) -> some View {
        ForEach(ids, id: \.self) { id in
            if let session = snapshot.session(id) {
                RemoteAgentRow(
                    session: session,
                    isSelected: isTerminalPage && controller.selectedSession == RemoteSessionRef(hubId: hubId, sessionId: id),
                    select: {
                        controller.select(RemoteSessionRef(hubId: hubId, sessionId: id))
                        showTerminal()
                    },
                    close: { Task { await controller.closeSession(RemoteSessionRef(hubId: hubId, sessionId: id)) } })
            }
        }
    }

    private func start(_ checkout: RemoteCheckoutNode, _ kind: RemoteSessionKind) {
        Task { await controller.startSession(hubId: hubId, checkoutPath: checkout.path, kind: kind) }
    }
}

/// Daraltılmış sidebar'da bağlı hub'ın terminalleri: durum + kimlik ikonu, ipucunda başlık.
private struct RemoteCollapsedAgents: View {
    let hubId: String
    let snapshot: RemoteHubSnapshot
    let controller: RemoteControllerStore
    let isTerminalPage: Bool
    let showTerminal: () -> Void

    /// Ağaç sırasıyla (projeler → checkout'lar → Other) tekil terminal kimlikleri.
    private var ids: [String] {
        var seen = Set<String>()
        let all = snapshot.projects.flatMap { $0.checkouts.flatMap(\.agentIds) } + snapshot.others.flatMap(\.agentIds)
        return all.filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            ForEach(ids, id: \.self) { id in
                if let session = snapshot.session(id) {
                    let ref = RemoteSessionRef(hubId: hubId, sessionId: id)
                    let isSelected = isTerminalPage && controller.selectedSession == ref
                    HoverReader { isHovering in
                        VStack(spacing: 0) {
                            TerminalIdentityIcon(provider: session.provider)
                            AgentActivityIcon(state: AgentActivityState(
                                status: TerminalStatus(rawValue: session.status) ?? .idle,
                                isAwaitingDecision: session.awaitingDecision), size: .caption)
                        }
                        .frame(width: Theme.Row.control, height: Theme.Row.control)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .fill(isSelected || isHovering ? Theme.bgElevated : Color.clear))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            controller.select(ref)
                            showTerminal()
                        }
                        .help("\(session.repoName) / \(session.title?.isEmpty == false ? session.title! : (session.provider?.rawValue.capitalized ?? "Shell"))")
                    }
                }
            }
        }
    }
}

private struct RemoteAgentRow: View {
    let session: RemoteSessionInfo
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HoverReader { isHovering in
            HStack(spacing: Theme.Spacing.sm) {
                AgentActivityIcon(state: AgentActivityState(
                    status: TerminalStatus(rawValue: session.status) ?? .idle,
                    isAwaitingDecision: session.awaitingDecision))
                TerminalIdentityIcon(provider: session.provider)
                Text(title)
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, Theme.Spacing.xl)
            .padding(.trailing, Theme.Spacing.sm)
            .frame(height: Theme.Row.compact)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(isSelected ? Theme.bgElevated : (isHovering ? Theme.bgElevated.opacity(Self.hoverOpacity) : Color.clear)))
            .contentShape(Rectangle())
            .onTapGesture(perform: select)
            .contextMenu {
                Button("Close Terminal", role: .destructive, action: close)
            }
        }
    }

    private var title: String {
        if let title = session.title, !title.isEmpty { return title }
        return session.provider?.rawValue.capitalized ?? "Shell"
    }

    private static let hoverOpacity = 0.5
}
