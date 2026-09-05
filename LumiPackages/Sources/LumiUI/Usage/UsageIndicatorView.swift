import LumiKit
import LumiState
import SwiftUI

/// Topbar'da duran kompakt kullanım göstergesi (design/05, karar 32): sağlayıcı
/// marka ikonu + 5 saatlik oturum yüzdesi (örn. "15%"). Tıklamada tüm limitleri
/// progress bar + reset süreleriyle gösteren popover açılır; popover'da manuel
/// refresh butonu vardır. Her açık sağlayıcı için bir örnek çizilir.
///
/// Gösterge gerçek bir `Button`'dır (Faz 7.6): `onTapGesture` klavye ve
/// VoiceOver için erişilemezdi.
public struct UsageIndicatorView: View {
    private let store: UsageStore
    @State private var isPresented = false

    public init(store: UsageStore) {
        self.store = store
    }

    public var body: some View {
        Button { isPresented.toggle() } label: { compact }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .help("\(store.provider.displayName) usage")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                UsagePopover(store: store)
            }
    }

    private var compact: some View {
        // 5pt: ölçek dışı ara değer (v1 paritesi korunuyor).
        HStack(spacing: 5) {
            ProviderIcon(provider: store.provider, size: .body)
            Text(label)
                // 11.5pt → ölçekte `label` (11); yuvarlama asla büyütmez.
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
        if let percent = store.fiveHourPercent { return "\(percent)%" }
        if store.isLoading { return "…" }
        return "—"
    }

    private var accessibilityLabel: String {
        guard let percent = store.fiveHourPercent else {
            return "\(store.provider.displayName) usage, unavailable"
        }
        return "\(store.provider.displayName) usage, \(percent) percent"
    }

    private var tint: Color {
        guard let percent = store.fiveHourPercent else { return Theme.textSecondary }
        return UsageLevel(percent: percent).color
    }
}

/// Tüm kullanım pencerelerini + refresh'i gösteren popover içeriği.
private struct UsagePopover: View {
    let store: UsageStore

    /// Popover'ın sabit genişliği ve iç kenar payı; ikisi de ölçek dışı ara
    /// değerler (v1 paritesi).
    private enum Metrics {
        static let width: CGFloat = 320
        static let inset: CGFloat = 14
        static let rowInset: CGFloat = 10
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
            ProviderIcon(provider: store.provider, size: .base)
            Text("\(store.provider.displayName) Usage")
                .font(Theme.Typography.mono(.base, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            refreshButton
        }
        .padding(.horizontal, Metrics.inset)
        .padding(.vertical, Metrics.rowInset)
    }

    /// `IconButton` değil: yükleme sırasında ikonun yerini bir `ProgressView`
    /// alır, yani "ikonu-tek buton" sözleşmesine girmez.
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
        .accessibilityLabel("Refresh \(store.provider.displayName) usage")
        .help(store.canRefresh ? "Refresh" : "Too frequent — wait a bit")
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = store.snapshot {
            VStack(alignment: .leading, spacing: Metrics.inset) {
                // Limit sayısı CLI'a göre değişir (model satırları eklenip
                // kaldırılabilir) → listeyi olduğu gibi gez.
                ForEach(snapshot.limits) { limit in
                    UsageWindowRow(title: limit.displayTitle, window: limit.window)
                }
                if snapshot.limits.isEmpty {
                    Text("No limit reported.")
                        .font(Theme.Typography.bodyMono)
                        .foregroundStyle(Theme.textSecondary)
                }
                if snapshot.mode == .apiKey {
                    Text("API key mode — no subscription limit.")
                        .font(Theme.Typography.labelMono)
                        .foregroundStyle(Theme.textMuted)
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
            Text(store.errorMessage ?? "No usage data.")
                .font(Theme.Typography.bodyMono)
                .foregroundStyle(Theme.error)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Alt bilgi Settings'teki satırla AYNI bileşendir (refactor 7.9);
    /// `.idle` durumunda hiç çizilmez.
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

/// Tek pencere satırı: başlık + yüzde + progress bar + reset zamanı.
/// (internal — `fillFraction` clamp'i birim testten görünür olsun diye.)
struct UsageWindowRow: View {
    let title: String
    let window: UsageWindow

    /// Progress bar yüksekliği; yarıçap `Radius.sm` (4) yüksekliğin yarısına
    /// (3) kırpılır, yani v1'deki 3pt köşeyle birebir aynı çizilir.
    private static let barHeight: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(title)
                    .font(Theme.Typography.bodyMono)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(percentText)
                    .font(Theme.Typography.mono(.body, weight: .semibold))
                    .foregroundStyle(percentColor)
            }
            progressBar
            if !resetText.isEmpty {
                Text(resetText)
                    .font(Theme.Typography.captionMono)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(Theme.bgDeep)
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(percentColor)
                    .frame(width: geo.size.width * fillFraction)
            }
        }
        .frame(height: Self.barHeight)
        .accessibilityHidden(true)
    }

    var fillFraction: CGFloat {
        guard let percent = window.percentUsed else { return 0 }
        return CGFloat(min(100, max(0, percent))) / 100
    }

    private var percentText: String {
        window.percentUsed.map { "\($0)%" } ?? "—"
    }

    private var percentColor: Color {
        window.percentUsed.map { UsageLevel(percent: $0).color } ?? Theme.textMuted
    }

    private var resetText: String {
        UsageStatusFormatter.resetText(for: window)
    }
}

#if DEBUG
#Preview("UsageIndicatorView") {
    HStack(spacing: Theme.Spacing.lg) {
        ForEach(AgentProvider.allCases, id: \.self) { provider in
            UsageIndicatorView(store: .preview(provider: provider))
        }
    }
    .padding(Theme.Spacing.xxl)
    .background(Theme.bgDeep)
}

#Preview("UsagePopover") {
    UsagePopover(store: .preview(provider: .claude))
        .background(Theme.bgDeep)
}
#endif
