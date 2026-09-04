import LumiKit
import LumiState
import SwiftUI

/// Topbar'da duran kompakt kullanım göstergesi (design/05, karar 32): sağlayıcı
/// marka ikonu + 5 saatlik oturum yüzdesi (örn. "15%"). Tıklamada tüm limitleri
/// progress bar + reset süreleriyle gösteren popover açılır; popover'da manuel
/// refresh butonu vardır. Her açık sağlayıcı için bir örnek çizilir.
public struct UsageIndicatorView: View {
    private let store: UsageStore
    @State private var isPresented = false

    public init(store: UsageStore) {
        self.store = store
    }

    public var body: some View {
        compact
            .contentShape(Rectangle())
            .onTapGesture { isPresented.toggle() }
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                UsagePopover(store: store)
            }
            .help("\(store.provider.displayName) usage")
    }

    private var compact: some View {
        HStack(spacing: 5) {
            ProviderIcon(provider: store.provider, size: 12)
            Text(label)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 8)
        .frame(height: TopBarMetrics.controlHeight)
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1)
        )
    }

    private var label: String {
        if let percent = store.fiveHourPercent { return "\(percent)%" }
        if store.isLoading { return "…" }
        return "—"
    }

    private var tint: Color {
        guard let percent = store.fiveHourPercent else { return Theme.textSecondary }
        return UsageTint.color(for: percent)
    }
}

/// Sağlayıcı marka ikonu (Orca glyph'leri, SVG). Kaynak yüklenemezse SF
/// Symbol'e düşülür — gösterge ikonsuz kalmaz.
struct ProviderIcon: View {
    let provider: AgentProvider
    var size: CGFloat = 12

    var body: some View {
        if let icon = LumiAssets.providerIcon(provider) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.system(size: size))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Kullanım yüzdesi → renk eşiği (yeşil < %50 ≤ sarı < %80 ≤ kırmızı).
enum UsageTint {
    static func color(for percent: Int) -> Color {
        switch percent {
        case ..<50: return Theme.success
        case ..<80: return Theme.warning
        default: return Theme.error
        }
    }
}

/// Tüm kullanım pencerelerini + refresh'i gösteren popover içeriği.
private struct UsagePopover: View {
    let store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            content
                .padding(14)
            footer
        }
        .frame(width: 320)
        .background(Theme.bgElevated)
    }

    private var header: some View {
        HStack(spacing: 6) {
            ProviderIcon(provider: store.provider, size: 13)
            Text("\(store.provider.displayName) Usage")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            refreshButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .frame(width: 26, height: 26)
            .foregroundStyle(store.canRefresh ? Theme.accentPrimary : Theme.textMuted)
            .background(Theme.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!store.canRefresh)
        .help(store.canRefresh ? "Refresh" : "Too frequent — wait a bit")
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = store.snapshot {
            VStack(alignment: .leading, spacing: 14) {
                // Limit sayısı CLI'a göre değişir (model satırları eklenip
                // kaldırılabilir) → listeyi olduğu gibi gez.
                ForEach(snapshot.limits) { limit in
                    UsageWindowRow(title: limit.displayTitle, window: limit.window)
                }
                if snapshot.limits.isEmpty {
                    Text("No limit reported.")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                if snapshot.mode == .apiKey {
                    Text("API key mode — no subscription limit.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                }
            }
        } else if store.isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading…")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            Text(store.errorMessage ?? "No usage data.")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.error)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if store.snapshot != nil || store.errorMessage != nil {
            VStack(alignment: .leading, spacing: 4) {
                Rectangle().fill(Theme.border).frame(height: 1)
                VStack(alignment: .leading, spacing: 3) {
                    if let fetchedAt = store.snapshot?.fetchedAt {
                        Text("Last updated: \(Self.timeFormatter.string(from: fetchedAt))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textMuted)
                    }
                    // Snapshot korunurken hata (güncellenemedi) — görünür (karar 5).
                    if store.snapshot != nil, let error = store.errorMessage {
                        Text("Update failed: \(error)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

/// Tek pencere satırı: başlık + yüzde + progress bar + reset zamanı.
/// (internal — `fillFraction` clamp'i birim testten görünür olsun diye.)
struct UsageWindowRow: View {
    let title: String
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(percentText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(percentColor)
            }
            progressBar
            if !resetText.isEmpty {
                Text(resetText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.bgDeep)
                RoundedRectangle(cornerRadius: 3)
                    .fill(percentColor)
                    .frame(width: geo.size.width * fillFraction)
            }
        }
        .frame(height: 6)
    }

    var fillFraction: CGFloat {
        guard let percent = window.percentUsed else { return 0 }
        return CGFloat(min(100, max(0, percent))) / 100
    }

    private var percentText: String {
        window.percentUsed.map { "\($0)%" } ?? "—"
    }

    private var percentColor: Color {
        window.percentUsed.map(UsageTint.color(for:)) ?? Theme.textMuted
    }

    private var resetText: String {
        guard !window.resetsRaw.isEmpty else { return "" }
        var text = "Resets: \(window.resetsRaw)"
        if let resetsAt = window.resetsAt {
            text += " · " + Self.relativeFormatter.localizedString(for: resetsAt, relativeTo: Date())
        }
        return text
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en")
        formatter.unitsStyle = .full
        return formatter
    }()
}
