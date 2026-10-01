import LumiKit
import LumiState
import SwiftUI

/// Settings ▸ Accounts (karar 56): Claude hesaplarını ekle, yeniden doğrula,
/// sil ve aralarında geçiş yap.
///
/// Hesap eklemek ZORUNLU değildir — Lumi hiç hesap eklenmemişken kullanıcının
/// kendi `~/.claude` oturumuyla ("System default") çalışır.
struct AccountsSettingsTab: SettingsTabContent {
    static let tab: SettingsTab = .accounts

    @Shell private var shell

    init() {}

    private var store: ClaudeAccountStore { shell.claudeAccounts }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LumiSectionTitle(
                title: "Accounts",
                description: "Switch between Claude and Codex logins without signing in again."
            )
            SectionHeader(title: "Claude", icon: "person.crop.circle")
                .padding(.bottom, Theme.Spacing.md)
            InfoCard(
                "Optional. Each account's credentials stay in your macOS Keychain; switching "
                    + "writes the selected account into the files the Claude Code CLI reads. "
                    + ClaudeAccountText.restartNotice
            )
            .padding(.bottom, Theme.Spacing.xxl)
            environmentWarning
            addRow
                .padding(.bottom, Theme.Spacing.lg)
            accountList
                .padding(.bottom, Theme.Spacing.xxl)
            CodexAccountsSettingsSection()
            Spacer(minLength: 0)
        }
        .task { await store.load() }
    }

    /// Ortamdaki bir auth değişkeni switch'i etkisiz kılıyorsa sebebini
    /// söyle (karar 56): CLI o değişkeni gördüğünde Keychain'e hiç bakmaz.
    @ViewBuilder
    private var environmentWarning: some View {
        let keys = ClaudeAuthEnvironment.conflicts()
        if !keys.isEmpty {
            InfoCard(
                "\(keys.joined(separator: ", ")) is set in Lumi's environment. The Claude CLI "
                    + "prefers it over the account you pick here, so switching has no effect "
                    + "until you unset it. The same applies to values exported from your shell "
                    + "profile, which Lumi cannot see."
            )
            .padding(.bottom, Theme.Spacing.lg)
        }
    }

    // MARK: - Ekleme

    private var addRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            LumiBrowseButton(icon: "plus", label: "Add Account") {
                Task { await store.addAccount() }
            }
            .disabled(store.isBusy)
            .opacity(store.isBusy ? 0.5 : 1)
            if store.isSigningIn {
                ProgressView().controlSize(.small)
                Text("Finish the sign-in in your browser…")
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textMuted)
                // Cancel yeniden doğrulamada da görünür: tarayıcı akışı yarıda
                // kalırsa `isBusy` login timeout'u dolana kadar bütün satırları
                // kilitli tutuyor, kullanıcı hesap değiştiremiyordu.
                LumiBrowseButton(icon: "xmark", label: "Cancel") {
                    Task { await store.cancelPendingLogin() }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Liste

    private var accountList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ClaudeAccountRow(
                title: ClaudeAccountText.systemDefaultTitle,
                subtitle: store.systemDefaultEmail ?? ClaudeAccountText.systemDefaultSubtitle,
                isActive: store.isActive(.systemDefault),
                isWorking: store.activity == .switching(to: .systemDefault),
                isDisabled: store.isBusy
            ) {
                Task { await store.select(.systemDefault) }
            }
            ForEach(store.accounts) { account in
                row(for: account)
            }
        }
    }

    private func row(for account: ClaudeAccount) -> some View {
        ClaudeAccountRow(
            title: account.email,
            subtitle: ClaudeAccountText.subtitle(for: account),
            isActive: store.isActive(.account(account.id)),
            isWorking: isWorking(account),
            isDisabled: store.isBusy,
            action: { Task { await store.select(.account(account.id)) } },
            trailing: {
                HStack(spacing: Theme.Spacing.xs) {
                    IconButton(systemName: "arrow.clockwise", label: "Re-authenticate") {
                        Task { await store.reauthenticate(account) }
                    }
                    IconButton(systemName: "trash", label: "Remove", role: .destructive) {
                        // Geri alınamaz: onay dialogundan geçer (karar 56).
                        shell.dialogs.present(.removeClaudeAccount(
                            RemoveClaudeAccountDialogState(
                                account: account,
                                isActive: store.isActive(.account(account.id))
                            )
                        ))
                    }
                }
                .disabled(store.isBusy)
                .opacity(store.isBusy ? 0.5 : 1)
            }
        )
    }

    private func isWorking(_ account: ClaudeAccount) -> Bool {
        switch store.activity {
        case .switching(to: .account(account.id)),
             .reauthenticating(accountID: account.id),
             .removing(accountID: account.id):
            return true
        default:
            return false
        }
    }

}

#if DEBUG
#Preview("Accounts") {
    SettingsTabPreview(.accounts)
}
#endif
