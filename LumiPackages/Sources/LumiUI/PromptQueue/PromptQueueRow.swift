import SwiftUI

/// Kuyruktaki tek prompt satırı: sıra no + metin önizleme + sil butonu.
/// Hover state'i `HoverReader`'ın içindedir (Faz 7.2).
struct PromptQueueRow: View {
    let index: Int
    let text: String
    let onDelete: () -> Void

    /// Sıra numarası kolonunun genişliği — ölçek dışı sabit.
    private static let ordinalWidth: CGFloat = 18

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Text("\(index + 1)")
                .font(Theme.Typography.mono(.label, weight: .bold))
                .foregroundStyle(Theme.textMuted)
                .frame(width: Self.ordinalWidth, alignment: .trailing)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.bodyMono)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            IconButton(
                systemName: "xmark.circle.fill",
                label: "Remove prompt \(index + 1) from queue",
                size: .body,
                weight: .regular,
                side: nil,
                role: .destructive,
                showsHoverBackground: false,
                action: onDelete
            )
        }
        .padding(.vertical, Theme.Spacing.sm)
        // 10pt: ölçek dışı ara değer (v1 paritesi korunuyor).
        .padding(.horizontal, 10)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }
}

#if DEBUG
#Preview("PromptQueueRow") {
    VStack(spacing: Theme.Spacing.xs) {
        PromptQueueRow(index: 0, text: "Run the full test suite and report failures") {}
        PromptQueueRow(
            index: 1,
            text: "Refactor the terminal grid so the fit math lives in one place, "
                + "then update the integration test accordingly.",
            onDelete: {}
        )
    }
    .padding(Theme.Spacing.xl)
    .frame(width: 520)
    .background(Theme.bgElevated)
}
#endif
