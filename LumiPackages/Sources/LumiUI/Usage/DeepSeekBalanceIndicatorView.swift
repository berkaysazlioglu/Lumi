import LumiKit
import LumiState
import SwiftUI

/// Topbar'daki DeepSeek bakiye göstergesi (karar 75): glyph + toplam bakiye
/// (örn. "$1.69"). Tıklamada hesabın üç tutarını + kullanılabilirliği gösteren
/// popover açılır; popover'da manuel yenileme vardır.
///
/// Kullanım göstergesinden (`UsageIndicatorView`) bilinçli olarak AYRI bir
/// bileşendir: DeepSeek'in genel API'si limit penceresi ya da yüzde döndürmez,
/// dolayısıyla çizilecek bir dolgu barı ve tempo çizgisi de yoktur (karar 74).
public struct DeepSeekBalanceIndicatorView: View {
    private let store: DeepSeekBalanceStore
    @State private var isPresented = false

    public init(store: DeepSeekBalanceStore) {
        self.store = store
    }

    public var body: some View {
        Button { isPresented.toggle() } label: { compact }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .help("DeepSeek balance")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                DeepSeekBalancePopover(store: store)
            }
    }

    private var compact: some View {
        // 5pt: ölçek dışı ara değer — kullanım göstergesiyle aynı ritim.
        HStack(spacing: Theme.scaled(5)) {
            DeepSeekIcon(size: .body)
            Text(label)
                .font(Theme.Typography.mono(.label, weight: .semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: TopBarMetrics.controlHeight)
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
        )
        .contentShape(Rectangle())
    }

    private var label: String {
        if let text = DeepSeekBalanceFormatter.compactLabel(store.balance) { return text }
        if store.isLoading { return "…" }
        return "—"
    }

    private var accessibilityLabel: String {
        guard let text = DeepSeekBalanceFormatter.compactLabel(store.balance) else {
            return "DeepSeek balance, unavailable"
        }
        return "DeepSeek balance, \(text)"
    }

    /// Bakiye bitmişse ya da sunucu "kullanılamaz" diyorsa kırmızı: rakam
    /// doğru olsa bile istek atılamıyor olabilir.
    private var tint: Color {
        guard let balance = store.balance else { return Theme.textSecondary }
        return balance.isAvailable ? Theme.textPrimary : Theme.error
    }
}

/// Bakiye ayrıntıları + yenileme.
private struct DeepSeekBalancePopover: View {
    let store: DeepSeekBalanceStore

    /// Kullanım popover'ıyla aynı ölçüler (ölçek dışı ara değerler).
    private enum Metrics {
        static var width: CGFloat { Theme.scaled(320) }
        static var inset: CGFloat { Theme.scaled(14) }
        static var rowInset: CGFloat { Theme.scaled(10) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
            content
                .padding(Metrics.inset)
            footer
        }
        .frame(width: Metrics.width)
        .background(Theme.bgElevated)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            DeepSeekIcon(size: .base)
            Text("DeepSeek Balance")
                .font(Theme.Typography.mono(.base, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            refreshButton
        }
        .padding(.horizontal, Metrics.inset)
        .padding(.vertical, Metrics.rowInset)
    }

    private var refreshButton: some View {
        Button {
            Task { await store.refresh() }
        } label: {
            Group {
                if store.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(Theme.Typography.ui(.body, weight: .semibold))
                }
            }
            .frame(width: TopBarMetrics.controlHeight, height: TopBarMetrics.controlHeight)
            .foregroundStyle(store.canRefresh ? Theme.accentPrimary : Theme.textMuted)
            .background(Theme.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!store.canRefresh)
        .accessibilityLabel("Refresh DeepSeek balance")
        .help(store.canRefresh ? "Refresh" : "Too frequent — wait a bit")
    }

    @ViewBuilder
    private var content: some View {
        if let balance = store.balance {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                availabilityRow(balance.isAvailable)
                // Hesap listesi sunucudan geldiği gibi gezilir: DeepSeek CNY ve
                // USD hesaplarını ayrı satırlar hâlinde dönebilir.
                ForEach(balance.accounts) { account in
                    accountRows(account)
                }
                if balance.accounts.isEmpty {
                    Text("No balance reported.")
                        .font(Theme.Typography.bodyMono)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } else if store.isLoading {
            HStack(spacing: Theme.Spacing.md) {
                ProgressView().controlSize(.small)
                Text("Loading…")
                    .font(Theme.Typography.bodyMono)
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            Text(store.errorMessage ?? "No balance data.")
                .font(Theme.Typography.bodyMono)
                .foregroundStyle(Theme.error)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func availabilityRow(_ isAvailable: Bool) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: isAvailable ? "checkmark.circle" : "exclamationmark.triangle")
                .font(Theme.Typography.ui(.body))
                .foregroundStyle(isAvailable ? Theme.success : Theme.warning)
            Text(isAvailable ? "Available for API calls" : "Not available for API calls")
                .font(Theme.Typography.bodyMono)
                .foregroundStyle(isAvailable ? Theme.textSecondary : Theme.warning)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func accountRows(_ account: DeepSeekBalance.Account) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            amountRow("Total", account.total, account, emphasized: true)
            amountRow("Topped up", account.toppedUp, account)
            amountRow("Granted", account.granted, account)
        }
    }

    private func amountRow(
        _ title: String,
        _ value: Decimal?,
        _ account: DeepSeekBalance.Account,
        emphasized: Bool = false
    ) -> some View {
        HStack {
            Text(title)
                .font(Theme.Typography.bodyMono)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(DeepSeekBalanceFormatter.amount(value, currency: account.currency))
                .font(Theme.Typography.mono(.body, weight: emphasized ? .semibold : .regular))
                .foregroundStyle(emphasized ? Theme.textPrimary : Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Kullanım popover'ıyla AYNI durum satırı bileşeni (refactor 7.9).
    @ViewBuilder
    private var footer: some View {
        if store.statusKind != .idle {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
                UsageStatusRow(kind: store.statusKind)
                    .padding(.horizontal, Metrics.inset)
                    .padding(.bottom, Metrics.rowInset)
            }
        }
    }
}

#if DEBUG
#Preview("DeepSeekBalanceIndicator") {
    HStack(spacing: Theme.Spacing.lg) {
        DeepSeekBalanceIndicatorView(store: .preview)
    }
    .padding(Theme.Spacing.xxl)
    .background(Theme.bgDeep)
}

#Preview("DeepSeekBalancePopover") {
    DeepSeekBalancePopover(store: .preview)
        .background(Theme.bgDeep)
}
#endif
