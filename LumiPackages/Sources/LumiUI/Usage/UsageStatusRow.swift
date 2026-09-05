import Foundation
import LumiKit
import SwiftUI

/// Kullanım kontrolünün durum satırı (refactor 7.9).
///
/// Aynı üçlü (yükleniyor / hata / son kontrol) iki yerde iki farklı davranışla
/// çiziliyordu: topbar popover'ının alt bilgisi ve Settings'teki satır. Bileşen
/// tek; kaynağı `UsageStore.statusKind`. `.staleWithError` iki satır çizer —
/// veri korunurken hatanın görünmesi bağlayıcıdır (karar 5).
struct UsageStatusRow: View {
    let kind: UsageStatusKind
    /// Sağlayıcı ikonu yalnız gösterge dışındaki kullanımlarda (Settings)
    /// çizilir; popover başlığında ikon zaten var.
    var provider: AgentProvider?

    /// Satırın tipografisi ölçeğin `label` (11) basamağıdır: ikon da metinle
    /// aynı basamaktan beslenir. Yatay boşluk (5) ve satır arası (3) ölçek dışı
    /// ara değerlerdir — v1 paritesi korunuyor.
    private enum Metrics {
        static let size: Theme.Typography.Size = .label
        static let spacing: CGFloat = 5
        static let lineSpacing: CGFloat = 3
    }

    var body: some View {
        if case .idle = kind {
            EmptyView()
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.spacing) {
                if let provider {
                    ProviderIcon(provider: provider, size: Metrics.size)
                }
                VStack(alignment: .leading, spacing: Metrics.lineSpacing) {
                    lines
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var lines: some View {
        switch kind {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: Metrics.spacing) {
                ProgressView().controlSize(.small)
                text("Checking…", color: Theme.textMuted)
            }
        case .failed(let message):
            labelled("exclamationmark.triangle", Theme.accentPrimary) {
                text("Last check failed: \(message)", color: Theme.textMuted)
            }
        case .updated(let fetchedAt):
            checkedLine(fetchedAt)
        case .staleWithError(let fetchedAt, let message):
            checkedLine(fetchedAt)
            labelled("exclamationmark.triangle", Theme.warning) {
                text("Update failed: \(message)", color: Theme.warning)
            }
        }
    }

    private func checkedLine(_ fetchedAt: Date) -> some View {
        labelled("checkmark.circle", Theme.accentCyan) {
            text("Last checked", color: Theme.textSecondary)
            text(UsageStatusFormatter.clockText(fetchedAt), color: Theme.textMuted)
        }
    }

    private func labelled<Content: View>(
        _ systemImage: String,
        _ tint: Color,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        HStack(spacing: Metrics.spacing) {
            Image(systemName: systemImage)
                .font(Theme.Typography.ui(Metrics.size))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            content()
        }
    }

    private func text(_ value: String, color: Color) -> some View {
        Text(value)
            .font(Theme.Typography.mono(Metrics.size))
            .foregroundStyle(color)
            .lineLimit(2)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
#Preview("UsageStatusRow") {
    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
        UsageStatusRow(kind: .loading, provider: .claude)
        UsageStatusRow(kind: .updated(fetchedAt: .now), provider: .claude)
        UsageStatusRow(kind: .failed(message: "OAuth token not found"), provider: .codex)
        UsageStatusRow(
            kind: .staleWithError(fetchedAt: .now, message: "HTTP 503"),
            provider: .codex
        )
    }
    .padding(Theme.Spacing.xxl)
    .frame(width: 360, alignment: .leading)
    .background(Theme.bgElevated)
}
#endif
