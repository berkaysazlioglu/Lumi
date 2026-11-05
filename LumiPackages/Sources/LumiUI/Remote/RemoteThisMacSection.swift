import LumiKit
import LumiState
import SwiftUI

/// Mac'ten Mac'e ağ: token yoksa oluştur / katıl, varsa kopyala / ayrıl (docs/design/08).
struct RemoteNetworkSection: View {
    let remote: RemoteStore

    @State private var isJoining = false
    @State private var tokenDraft = ""
    @State private var joinError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            RemoteSectionHeader(title: "Network")
            if remote.hasNetwork {
                Text("Macs with the same network token see each other. Share it only with your own Macs.")
                    .modifier(RemoteHintStyle())
                HStack(spacing: Theme.Spacing.md) {
                    LumiActionButton(title: "Copy Token") { copyToken() }
                    LumiActionButton(title: "Leave", kind: .destructive) { Task { await remote.leaveNetwork() } }
                }
            } else if isJoining {
                LumiTextInput(text: $tokenDraft, placeholder: "Paste the network token", autofocus: true,
                              isSecure: true, onSubmit: join)
                if let joinError {
                    Text(joinError).font(Theme.Typography.labelMono).foregroundStyle(Theme.error)
                }
                HStack(spacing: Theme.Spacing.md) {
                    LumiActionButton(title: "Join", kind: .primary, action: join)
                    LumiActionButton(title: "Cancel") { isJoining = false; joinError = nil }
                }
            } else {
                Text("Create a network here, then join it from your other Macs with the same token.")
                    .modifier(RemoteHintStyle())
                HStack(spacing: Theme.Spacing.md) {
                    LumiActionButton(title: "Create Network", kind: .primary) { Task { await remote.createNetwork() } }
                    LumiActionButton(title: "Join Network…") { isJoining = true }
                }
            }
        }
    }

    private func join() {
        Task {
            if await remote.joinNetwork(tokenDraft) {
                tokenDraft = ""
                isJoining = false
                joinError = nil
            } else {
                joinError = "That doesn't look like a network token."
            }
        }
    }

    private func copyToken() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(remote.config.networkToken, forType: .string)
    }
}

/// Bu Mac'in hub olarak paylaşılması: anahtar, ad, şifre, bağlı controller'lar.
struct RemoteThisMacSection: View {
    let remote: RemoteStore

    @State private var nameDraft = ""
    @State private var isEditingPassword = false
    @State private var passwordDraft = ""
    @State private var confirmDraft = ""
    @State private var passwordError: String?
    /// Şifre formu paylaşmayı açmak için mi açıldı (kaydedince paylaşım da açılır).
    @State private var shareAfterPassword = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            RemoteSectionHeader(title: "This Mac", trailing: statusLabel)
            LumiToggleRow(
                title: "Share This Mac",
                hint: "Other Macs on the network can open and drive terminals here with the password.",
                isOn: Binding(get: { remote.config.hubEnabled }, set: setSharing))
            HStack(spacing: Theme.Spacing.md) {
                LumiTextInput(text: $nameDraft, placeholder: remote.hubDisplayName, onSubmit: saveName)
                LumiActionButton(title: "Rename", action: saveName)
                    .disabled(nameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if isEditingPassword {
                passwordForm
            } else {
                HStack(spacing: Theme.Spacing.md) {
                    LumiActionButton(title: remote.hasHubPassword ? "Change Password…" : "Set Password…") {
                        shareAfterPassword = false
                        isEditingPassword = true
                    }
                    if remote.hasHubPassword {
                        LumiActionButton(title: "Remove Password", kind: .destructive) {
                            Task { try? await remote.removeHubPassword() }
                        }
                    }
                }
            }
            if !remote.hubControllers.isEmpty {
                controllers
            }
        }
        .onAppear { nameDraft = remote.config.hubName }
    }

    private var statusLabel: String? {
        guard remote.config.hubEnabled else { return nil }
        switch remote.hubState {
        case .connected: return "sharing"
        case .connecting: return "connecting…"
        case .disconnected: return remote.hasHubPassword ? "offline" : "needs password"
        }
    }

    private var passwordForm: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(shareAfterPassword ? "Set a password to share this Mac." : "Changing the password disconnects everyone.")
                .modifier(RemoteHintStyle())
            LumiTextInput(text: $passwordDraft, placeholder: "Password", autofocus: true, isSecure: true)
            LumiTextInput(text: $confirmDraft, placeholder: "Repeat password", isSecure: true, onSubmit: savePassword)
            if let passwordError {
                Text(passwordError).font(Theme.Typography.labelMono).foregroundStyle(Theme.error)
            }
            HStack(spacing: Theme.Spacing.md) {
                LumiActionButton(title: shareAfterPassword ? "Save & Share" : "Save", kind: .primary, action: savePassword)
                LumiActionButton(title: "Cancel") { resetPasswordForm() }
            }
        }
    }

    private var controllers: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(remote.hubControllers) { controller in
                Label(controller.name, systemImage: "desktopcomputer")
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textSecondary)
            }
            LumiActionButton(title: "Disconnect All", kind: .destructive) {
                Task { await remote.disconnectAllControllers() }
            }
        }
    }

    private func setSharing(_ enabled: Bool) {
        guard enabled, !remote.hasHubPassword else {
            Task { await remote.setHubEnabled(enabled) }
            return
        }
        shareAfterPassword = true
        isEditingPassword = true
    }

    private func saveName() {
        let name = nameDraft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task { await remote.setHubName(name) }
    }

    private func savePassword() {
        guard !passwordDraft.isEmpty else { passwordError = "Enter a password."; return }
        guard passwordDraft == confirmDraft else { passwordError = "The passwords don't match."; return }
        let password = passwordDraft, share = shareAfterPassword
        Task {
            do {
                try await remote.setHubPassword(password)
                if share { await remote.setHubEnabled(true) }
                resetPasswordForm()
            } catch {
                passwordError = "Couldn't save the password to the Keychain."
            }
        }
    }

    private func resetPasswordForm() {
        isEditingPassword = false
        shareAfterPassword = false
        passwordDraft = ""
        confirmDraft = ""
        passwordError = nil
    }
}

/// Remote sütununun bölüm başlığı.
struct RemoteSectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(Theme.Typography.mono(.caption, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
            Spacer()
            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(Theme.Typography.captionMono)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

struct RemoteHintStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.Typography.labelMono)
            .foregroundStyle(Theme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
