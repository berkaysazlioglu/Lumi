import LumiKit
import SwiftUI

/// Yatay terminal chip şeridi (refactor 6.7).
///
/// İki çağrı yeri vardı ve ikisi de BİREBİR aynı kodu taşıyordu: minimize
/// şeridi (`TerminalsRouteView`) ve maximize altındaki switcher
/// (`MaximizedTerminalView`). Tek fark, minimize şeridinin başındaki
/// "Minimized:" etiketi — o da opsiyonel parametre oldu.
///
/// Ölçüler değişmedi: 6pt aralık, 5pt köşe, 24pt şerit yüksekliği.
struct TerminalChipStrip: View {
    /// Chip başlığının üst sınırı: uzun terminal adları şeridi tek başına
    /// doldurup diğerlerini itiyordu; sığmayan ad "…" ile kırpılır.
    static var titleMaxWidth: CGFloat { Theme.scaled(160) }

    /// Şeridin başındaki muted etiket (minimize şeridi için "Minimized:").
    var label: String?
    let items: [TerminalMeta]
    let onSelect: (TerminalID) -> Void

    /// Karar 103: All Terminals'ta chip de checkout adını taşır.
    @Environment(\.terminalCheckoutLabels) private var checkoutLabels

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                if let label {
                    Text(label)
                        .font(Theme.Typography.mono(.label))
                        .foregroundStyle(Theme.textMuted)
                }
                ForEach(items) { meta in
                    chip(meta)
                }
            }
        }
        .frame(height: Theme.Spacing.xxl)
    }

    private func chip(_ meta: TerminalMeta) -> some View {
        Button {
            onSelect(meta.id)
        } label: {
            // 5/3pt: ölçek dışı ara değerler (v1 paritesi korunuyor).
            HStack(spacing: Theme.scaled(5)) {
                Circle()
                    .fill(Theme.statusColor(for: meta.status))
                    .frame(width: Theme.Spacing.sm, height: Theme.Spacing.sm)
                    .accessibilityHidden(true)
                Text(meta.displayTitle)
                    .font(Theme.Typography.mono(.label))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: Self.titleMaxWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let checkout = checkoutLabels[meta.repoPath] {
                    Text(checkout)
                        .font(Theme.Typography.mono(.label))
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: Self.titleMaxWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.scaled(3))
            .background(Theme.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textSecondary)
        .accessibilityLabel(checkoutLabels[meta.repoPath].map { "\(meta.displayTitle) in \($0)" } ?? meta.displayTitle)
    }
}
