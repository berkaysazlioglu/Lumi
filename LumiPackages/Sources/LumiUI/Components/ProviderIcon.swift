import LumiKit
import SwiftUI

/// Sağlayıcı marka ikonu (Orca glyph'leri, SVG). Kaynak yüklenemezse SF
/// Symbol'e düşülür — gösterge ikonsuz kalmaz.
///
/// Faz 7.2'de `UsageIndicatorView`'dan çıkarıldı: üç ayrı yer (topbar
/// göstergesi, popover başlığı, Settings durum satırı) aynı ikonu çiziyor ve
/// boyutu ham CGFloat olarak geçiyordu. Boyut artık tipografi ölçeğinin bir
/// basamağı — ikon, yanındaki metinle aynı basamaktan beslenir.
///
/// Dekoratiftir: anlamı taşıyan metin (sağlayıcı adı / durum) hep yanındadır,
/// bu yüzden VoiceOver'dan gizlenir.
struct ProviderIcon: View {
    let provider: AgentProvider
    var size: Theme.Typography.Size = .body

    var body: some View {
        icon.accessibilityHidden(true)
    }

    @ViewBuilder
    private var icon: some View {
        if let image = LumiAssets.providerIcon(provider) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size.points, height: size.points)
        } else {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(Theme.Typography.ui(size))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

#if DEBUG
#Preview("ProviderIcon") {
    HStack(spacing: Theme.Spacing.lg) {
        ForEach(AgentProvider.allCases, id: \.self) { provider in
            HStack(spacing: Theme.Spacing.sm) {
                ProviderIcon(provider: provider, size: .label)
                ProviderIcon(provider: provider, size: .base)
                ProviderIcon(provider: provider, size: .display)
            }
        }
    }
    .padding(Theme.Spacing.xxl)
    .background(Theme.bgSurface)
}
#endif
