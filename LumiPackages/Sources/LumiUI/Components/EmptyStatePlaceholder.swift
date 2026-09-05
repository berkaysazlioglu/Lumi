import SwiftUI

/// "Burada bir şey yok" metni (Faz 7.2).
///
/// Beş kopyası vardı (boş terminal listesi, boş oturum listesi, boş file-tree /
/// arama sonucu, git panellerinin boş hâli, çözülemeyen görsel) ve puntoları
/// 11 ile 13 arasında gelişigüzel dağılmıştı. Üç yoğunluk basamağına indirildi.
struct EmptyStatePlaceholder<Accessory: View>: View {
    /// Kabına göre yoğunluk.
    enum Density {
        /// Panel satırı arasına giren tek satır (11pt, dar dolgu).
        case inline
        /// Panel bölümünün gövdesi (12pt).
        case panel
        /// Orta alanın tamamı (13pt, ortalanmış).
        case full
    }

    let text: String
    var density: Density = .panel
    @ViewBuilder var accessory: () -> Accessory

    init(
        _ text: String,
        density: Density = .panel,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.text = text
        self.density = density
        self.accessory = accessory
    }

    @ViewBuilder
    var body: some View {
        if density == .full {
            stack.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            stack.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stack: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text(text)
                .font(Theme.Typography.mono(size))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(density == .full ? .center : .leading)
            accessory()
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
    }

    private var size: Theme.Typography.Size {
        switch density {
        case .inline: return .label
        case .panel: return .body
        case .full: return .base
        }
    }

    private var horizontalPadding: CGFloat {
        switch density {
        case .inline: return Theme.Spacing.lg
        case .panel: return Theme.Spacing.xs
        case .full: return 0
        }
    }

    private var verticalPadding: CGFloat {
        switch density {
        case .inline: return Theme.Spacing.xs
        case .panel: return Theme.Spacing.xs
        case .full: return 0
        }
    }
}

#if DEBUG
#Preview("EmptyStatePlaceholder") {
    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
        EmptyStatePlaceholder("No uncommitted changes", density: .inline)
        EmptyStatePlaceholder("No active sessions")
        EmptyStatePlaceholder("No terminals in this repo", density: .full) {
            Text("(accessory)")
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.accentPrimary)
        }
    }
    .frame(width: 320, height: 320)
    .background(Theme.bgSurface)
}
#endif
