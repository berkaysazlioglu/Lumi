import AppKit
import LumiKit
import LumiState
import SwiftUI

/// Agent History ▸ Import ▸ Import from Server (karar 138).
///
/// Ekranın ortasında popup: bağlı değilse (ya da `Reconnect…`) kurulum
/// prompt'u + adres + token formu, bağlıysa solda yükleyenler, sağda oturum
/// listesi. Liste yalnız popup açılırken (5 dakikadan eskiyse) ve Refresh
/// düğmesiyle tazelenir.
public struct SessionShareBrowserOverlay: View {
    @Shell private var shell

    public init() {}

    static var panelWidth: CGFloat { Theme.scaled(900) }
    static var panelHeight: CGFloat { Theme.scaled(600) }

    public var body: some View {
        if let store = shell.sessionShare {
            ModalOverlay(onDismiss: { dismiss(store) }) {
                Panel(variant: .modal) {
                    VStack(spacing: 0) {
                        header(store)
                        SessionShareDivider()
                        if store.connectForm != nil {
                            SessionShareConnectForm(store: store)
                        } else {
                            SessionShareBrowserContent(store: store, defaultProjectPath: defaultProjectPath)
                        }
                    }
                }
                .frame(width: Self.panelWidth, height: Self.panelHeight)
            }
        }
    }

    /// Form açıkken kapatma: bağlıysa tarayıcıya döner, değilse popup kapanır.
    private func dismiss(_ store: SessionShareStore) {
        if store.connectForm != nil, store.isConnected {
            store.connectForm = nil
        } else {
            store.closeBrowser()
        }
    }

    /// Project picker'ın önce önerdiği proje: sağ panelin projesi.
    private var defaultProjectPath: String? {
        shell.navigation.toolsRepoPath.flatMap { shell.navigation.projectPath(containing: $0) ?? $0 }
    }

    private func header(_ store: SessionShareStore) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title(store))
                    .font(Theme.Typography.mono(.headline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle(store))
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }
            Spacer()
            if store.connectForm == nil, store.isConnected {
                refreshButton(store)
                SessionShareServerMenu(store: store)
            }
            IconButton(
                systemName: "xmark", label: "Close",
                side: Theme.scaled(28), cornerRadius: Theme.Radius.md, action: store.closeBrowser
            )
        }
        .padding(Theme.Spacing.xl)
    }

    private func title(_ store: SessionShareStore) -> String {
        guard let form = store.connectForm else { return store.server?.name ?? "Shared Sessions" }
        return form.isReconnect ? "Reconnect Session Server" : "Connect Session Server"
    }

    private func subtitle(_ store: SessionShareStore) -> String {
        if store.connectForm != nil { return "Share agent sessions with your team through a server you own" }
        var parts: [String] = []
        if let me = store.info?.me { parts.append("Signed in as \(me.name)") }
        if store.isRefreshing {
            parts.append("Refreshing…")
        } else if let date = store.lastRefreshedAt {
            parts.append("Updated \(RelativeTimeFormatter.label(date))")
        }
        return parts.isEmpty ? "Shared agent sessions" : parts.joined(separator: " · ")
    }

    private func refreshButton(_ store: SessionShareStore) -> some View {
        IconButton(
            systemName: "arrow.clockwise", label: "Refresh shared sessions",
            side: Theme.scaled(28), cornerRadius: Theme.Radius.md
        ) {
            Task { await store.refresh() }
        }
        .disabled(store.isRefreshing)
    }
}

/// Sunucu menüsü: kurulum prompt'u, yeniden bağlanma, bağlantıyı kesme.
private struct SessionShareServerMenu: View {
    let store: SessionShareStore
    @Shell private var shell
    @State private var isOpen = false

    var body: some View {
        IconButton(
            systemName: "ellipsis", label: "Server actions",
            side: Theme.scaled(28), cornerRadius: Theme.Radius.md
        ) { isOpen.toggle() }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            PopoverMenu(items: [
                .action("Copy Setup Prompt", icon: "doc.on.clipboard") { SessionSharePasteboard.copySetupPrompt(shell) },
                .action("Reconnect…", icon: "key") { store.beginConnect(isReconnect: true) },
                .divider,
                .action("Disconnect", icon: "bolt.horizontal", isDestructive: true) {
                    Task { await store.disconnect() }
                },
            ], dismiss: { isOpen = false })
        }
    }
}

/// Bağlanma formu — Tasks'in Connect akışının sadeleşmiş eşi: setup prompt'u,
/// adres, token; Connect discovery + listeyi dener, hata ayrıntısı ajana kopyalanır.
struct SessionShareConnectForm: View {
    @Bindable var store: SessionShareStore
    @Shell private var shell

    private var form: SessionShareStore.ConnectForm? { store.connectForm }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    LumiField(
                        title: "1 · Set up your server",
                        hint: "Paste the setup prompt into an agent working in your server's project. It builds the Lumi Sessions API, creates your user and prints an address and your personal token. Teammates get their own tokens from the server's add-user command."
                    ) {
                        HStack(spacing: Theme.Spacing.md) {
                            LumiActionButton(title: "Copy Setup Prompt", kind: .primary) {
                                SessionSharePasteboard.copySetupPrompt(shell)
                            }
                            Text("Lumi Sessions Protocol v1")
                                .font(Theme.Typography.labelMono)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    LumiField(title: "2 · Server address", hint: "https:// — or http://localhost while you develop") {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            LumiTextInput(text: binding(\.address), placeholder: "https://my-app.herokuapp.com")
                            if let problem = store.addressProblem {
                                Text(problem)
                                    .font(Theme.Typography.labelMono)
                                    .foregroundStyle(Theme.error)
                            }
                        }
                    }
                    LumiField(
                        title: "3 · Your token", hint: "Stored in your Keychain, sent only to this server",
                        isLast: form?.failure == nil
                    ) {
                        LumiTextInput(
                            text: binding(\.token), placeholder: "Paste your token", isSecure: true,
                            onSubmit: { Task { await store.connect() } }
                        )
                    }
                    if let failure = form?.failure {
                        LumiField(title: "Couldn't connect", hint: nil, isLast: true) {
                            SessionShareFailureView(failure: failure)
                        }
                    }
                }
                .padding(Theme.Spacing.xxl)
            }
            SessionShareDivider()
            HStack(spacing: Theme.Spacing.md) {
                Spacer()
                LumiActionButton(title: "Cancel") {
                    if store.isConnected { store.connectForm = nil } else { store.cancelConnect() }
                }
                LumiActionButton(title: form?.isVerifying == true ? "Connecting…" : "Connect", kind: .primary) {
                    Task { await store.connect() }
                }
                .disabled(!store.canSubmitConnect)
            }
            .padding(Theme.Spacing.xl)
        }
    }

    private func binding(_ path: WritableKeyPath<SessionShareStore.ConnectForm, String>) -> Binding<String> {
        Binding(
            get: { store.connectForm?[keyPath: path] ?? "" },
            set: { value in
                guard store.connectForm?[keyPath: path] != value else { return }
                store.connectForm?[keyPath: path] = value
                store.connectForm?.failure = nil
            }
        )
    }
}

/// Hata özeti + düzeltme ipucu + `Copy Report for Agent`.
struct SessionShareFailureView: View {
    let failure: SessionShareFailure
    @Shell private var shell

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(failure.summary)
                .font(Theme.Typography.bodyMono)
                .foregroundStyle(Theme.error)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text(failure.hint)
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            LumiActionButton(title: "Copy Report for Agent") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(failure.agentReport, forType: .string)
                shell.toasts.show(.success, title: "Copied error report", message: "Paste it into the agent that built your server.")
            }
        }
    }
}

struct SessionShareDivider: View {
    var body: some View {
        Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
    }
}

@MainActor
enum SessionSharePasteboard {
    static func copySetupPrompt(_ shell: ShellContext) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(SessionShareSetupPrompt.text, forType: .string)
        shell.toasts.show(.success, title: "Copied setup prompt", message: "Paste it into an agent working in your server's project.")
    }
}
