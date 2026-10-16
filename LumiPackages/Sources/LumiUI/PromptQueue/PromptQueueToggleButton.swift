import SwiftUI

/// Terminal topbar'ındaki kuyruk toggle butonu: liste ikonu + bekleyen prompt
/// sayısı baloncuğu. Duraklatıldıysa baloncuk renk değiştirir.
///
/// Hover state'i `HoverReader`'ın içindedir (Faz 7.2).
struct PromptQueueToggleButton: View {
    let count: Int
    let isPaused: Bool
    @Binding var isOpen: Bool
    /// Karar 120: renkli projenin kart header'ında ikon + sayaç proje renginde.
    @Environment(\.iconButtonTint) private var tint

    /// İkon kutusu ve sayaç baloncuğunun geometrisi — ölçek dışı sabitler.
    private enum Metrics {
        static var side: CGFloat { Theme.scaled(20) }
        static var bubbleSide: CGFloat { Theme.scaled(12) }
        static var bubblePadding: CGFloat { Theme.scaled(3) }
        static var bubbleOffsetX: CGFloat { Theme.scaled(4) }
        static var bubbleOffsetY: CGFloat { Theme.scaled(-2) }
    }

    var body: some View {
        HoverReader { isHovering in
            Button { isOpen.toggle() } label: {
                ZStack(alignment: .topTrailing) {
                    icon(isHovering: isHovering)
                    if count > 0 { countBubble }
                }
            }
            .buttonStyle(.plain)
        }
        .accessibilityLabel(accessibilityLabel)
        .help("Prompt queue")
    }

    private func icon(isHovering: Bool) -> some View {
        Image(systemName: isPaused ? "pause.rectangle" : "list.bullet.rectangle")
            .font(Theme.Typography.ui(.caption, weight: .bold))
            .foregroundStyle(iconColor(isHovering: isHovering))
            .frame(width: Metrics.side, height: Metrics.side)
            .background(isHovering || isOpen ? (tint?.hoverBackground ?? Theme.bgSurface) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .contentShape(Rectangle())
    }

    /// `Badge` DEĞİL: ortak rozet bir etiket kutusudur (soluk zemin, ölçek
    /// dolgusu). Bu ise ikonun köşesine binen dolu bir sayaç baloncuğu — kendi
    /// asgari kare ölçüsü ve dar dolgusu var. Sayı butonun erişilebilirlik
    /// etiketinde geçtiği için baloncuk VoiceOver'dan gizlenir.
    private var countBubble: some View {
        Text("\(count)")
            .font(Theme.Typography.rounded(.micro, weight: .bold))
            // Proje renkleri açık tonlar: beyaz yerine koyu metin okunur kalır.
            .foregroundStyle(tint == nil ? Color.white : Theme.bgDeep)
            .padding(.horizontal, Metrics.bubblePadding)
            .frame(minWidth: Metrics.bubbleSide, minHeight: Metrics.bubbleSide)
            .background(isPaused ? Theme.warning : (tint?.fill ?? Theme.accentVivid))
            .clipShape(Capsule())
            .offset(x: Metrics.bubbleOffsetX, y: Metrics.bubbleOffsetY)
            .accessibilityHidden(true)
    }

    private func iconColor(isHovering: Bool) -> Color {
        if isOpen || isHovering { return tint?.hover ?? Theme.textPrimary }
        if let tint { return count > 0 ? tint.hover : tint.rest }
        return count > 0 ? Theme.accentPrimary : Theme.textMuted
    }

    private var accessibilityLabel: String {
        let state = isPaused ? "paused" : "active"
        return count > 0
            ? "Prompt queue, \(state), \(count) queued"
            : "Prompt queue, \(state), empty"
    }
}

#if DEBUG
#Preview("PromptQueueToggleButton") {
    HStack(spacing: Theme.Spacing.xl) {
        PromptQueueToggleButton(count: 0, isPaused: false, isOpen: .constant(false))
        PromptQueueToggleButton(count: 3, isPaused: false, isOpen: .constant(false))
        PromptQueueToggleButton(count: 12, isPaused: true, isOpen: .constant(true))
    }
    .padding(Theme.Spacing.xxl)
    .background(Theme.bgElevated)
}
#endif
