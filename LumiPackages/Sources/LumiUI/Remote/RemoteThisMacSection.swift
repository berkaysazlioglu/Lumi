import LumiKit
import LumiState
import SwiftUI

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
                hint: "Other Macs on this server can open and drive terminals here with the password.",
                // Method referansı (`set: setSharing`) Swift 6.2.3 release IRGen'ini
                // çökertiyordu (@isolated(any) Binding<Bool> thunk'ı) — closure şart.
                isOn: Binding(get: { remote.config.hubEnabled }, set: { setSharing($0) }))
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
