import LumiKit
import LumiState
import SwiftUI

/// Relay sunucusu: Server URL + Server Token (karar 146, docs/design/09).
///
/// Remote route'unun `This Mac` ve `Mobile` sayfalarının ortak bileşeni — ikisi de
/// aynı `remote.json` alanlarını yazar, birinde girilen diğerinde de dolu görünür.
/// Lumi'ye adres gömülü değildir; adres ve token sunucunun dashboard'undan alınır.
struct RemoteServerSection: View {
    let remote: RemoteStore
    /// Controller directory'sinin reddi (yalnız `This Mac`'te bilinir).
    var directoryIssue: RemoteServerIssue?

    @State private var urlDraft = ""
    @State private var tokenDraft = ""
    @State private var formError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            RemoteSectionHeader(title: "Server", trailing: remote.hasServer ? nil : "not set")
            Text("Your Lumi relay server. Get the URL and a token from the server's dashboard.")
                .modifier(RemoteHintStyle())
            LumiTextInput(text: $urlDraft, placeholder: "wss://your-relay.example.com", onSubmit: save)
            LumiTextInput(text: $tokenDraft, placeholder: "Server token", isSecure: true, onSubmit: save)
            if let message = formError ?? issue?.message {
                Text(message)
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Theme.Spacing.md) {
                LumiActionButton(title: remote.hasServer ? "Save" : "Connect", kind: .primary, action: save)
                    .disabled(!isDirty)
                if remote.hasServer {
                    LumiActionButton(title: "Disconnect", kind: .destructive, action: disconnect)
                }
            }
        }
        .onAppear(perform: loadDrafts)
        .onChange(of: remote.config.relayUrl) { _, _ in loadDrafts() }
        .onChange(of: remote.config.serverToken) { _, _ in loadDrafts() }
    }

    private var issue: RemoteServerIssue? {
        remote.serverIssue ?? directoryIssue
    }

    private var isDirty: Bool {
        trimmed(urlDraft) != remote.config.relayUrl || trimmed(tokenDraft) != remote.config.serverToken
    }

    private func save() {
        let url = trimmed(urlDraft), token = trimmed(tokenDraft)
        guard RelayEndpoint.isValidAddress(url) else {
            formError = "Enter a ws:// or wss:// address."
            return
        }
        guard RelayEndpoint(url: url, token: token) != nil else {
            formError = "Enter the server token."
            return
        }
        formError = nil
        Task { await remote.setServer(url: url, token: token) }
    }

    private func disconnect() {
        formError = nil
        Task { await remote.setServer(url: "", token: "") }
    }

    private func loadDrafts() {
        urlDraft = remote.config.relayUrl
        tokenDraft = remote.config.serverToken
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
