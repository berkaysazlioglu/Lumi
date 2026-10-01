import LumiKit
import LumiState
import SwiftUI

/// Claude kullanım popover'ının hesap bölümü (karar 56).
///
/// Kapalı hâlde tek satır: aktif hesap. Açılınca System default + tüm
/// hesaplar listelenir ve bir satıra tıklamak switch'ler. En altta Settings ▸
/// Accounts'a giden bağlantı durur — ekleme/silme oraya aittir, popover
/// yalnız geçiş yapar.
struct ClaudeAccountSwitcher: View {
    let store: ClaudeAccountStore
    /// Settings'i Accounts sekmesinde açar; nil ise bağlantı çizilmez
    /// (preview).
    var openSettings: (() -> Void)?

    @State private var isExpanded = false

    /// Liste uzarsa popover'ı taşırmasın — kaydırılır.
    private static var maxListHeight: CGFloat { Theme.scaled(220) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            header
            if isExpanded {
                list
                Text(ClaudeAccountText.restartNotice)
                    .font(Theme.Typography.captionMono)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let openSettings {
                Button("Manage Accounts…", action: openSettings)
                    .buttonStyle(.plain)
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.accentPrimary)
            }
        }
        .task { await store.load() }
    }

    private var header: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Text("Account")
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textMuted)
                Text(store.activeLabel)
                    .font(Theme.Typography.mono(.label, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if store.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(Theme.Typography.ui(.caption, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Claude account: \(store.activeLabel)")
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                row(
                    .systemDefault,
                    title: ClaudeAccountText.systemDefaultTitle,
                    subtitle: store.systemDefaultEmail
                )
                ForEach(store.accounts) { account in
                    row(
                        .account(account.id),
                        title: account.email,
                        subtitle: account.organizationName
                    )
                }
            }
        }
        .frame(maxHeight: Self.maxListHeight)
    }

    private func row(
        _ selection: ClaudeAccountSelection, title: String, subtitle: String?
    ) -> some View {
        ClaudeAccountRow(
            title: title,
            subtitle: subtitle,
            isActive: store.isActive(selection),
            isWorking: store.activity == .switching(to: selection),
            isDisabled: store.isBusy
        ) {
            Task {
                await store.select(selection)
                isExpanded = false
            }
        }
    }
}
