import LumiKit
import SwiftUI

/// Commit satırındaki ref rozetleri (karar 40/45): en fazla iki rozet + "+N"
/// (Orca kuralı — dar sidebar'da ref listesi mesajı ezmemeli). Git History ve
/// Plastic History aynı bileşeni kullanır.
struct CommitRefBadges: View {
    let refs: [GitRef]
    /// Rozetin ait olduğu düğümün lane rengi; `isCurrent` ref accent alır.
    let colorIndex: Int
    /// Rozet metni (karar 46 eki: Plastic `…/parent/current` kısaltması);
    /// tooltip her zaman TAM adı gösterir.
    var displayName: (GitRef) -> String = { $0.name }
    /// Verilirse rozet bu genişliği aşamaz ve sığmayan metin rozet içinde
    /// sürekli kayar (dükkân tabelası); nil → Git davranışı (orta kırpma).
    var marqueeMaxWidth: CGFloat? = nil

    static let maxVisibleRefs = 2
    private static let badgeBorderOpacity = 0.6

    var body: some View {
        let visible = refs.prefix(Self.maxVisibleRefs)
        let hidden = refs.dropFirst(Self.maxVisibleRefs)
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(Array(visible)) { ref in
                badge(ref)
            }
            if !hidden.isEmpty {
                Text("+\(hidden.count)")
                    .font(Theme.Typography.ui(.caption))
                    .foregroundStyle(Theme.textMuted)
                    .help(hidden.map(\.name).joined(separator: ", "))
            }
        }
        .fixedSize()
    }

    private func badge(_ ref: GitRef) -> some View {
        let color = ref.isCurrent ? Theme.accentVivid : Theme.Graph.laneColor(colorIndex)
        return label(displayName(ref), color: color)
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.xxxs)
            .background(Theme.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(color.opacity(Self.badgeBorderOpacity), lineWidth: Theme.Stroke.hairline)
            )
            .help(Self.help(ref))
    }

    @ViewBuilder
    private func label(_ text: String, color: Color) -> some View {
        if let marqueeMaxWidth {
            MarqueeText(
                text: text,
                font: Theme.Typography.ui(.caption, weight: .medium),
                color: color,
                animating: true,
                trailingGap: Theme.Graph.refBadgeMarqueeGap,
                maxWidth: marqueeMaxWidth  // kısa ad rozeti daraltır; uzun ad tavana dayanır ve kayar
            )
        } else {
            Text(text)
                .font(Theme.Typography.ui(.caption, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    static func help(_ ref: GitRef) -> String {
        switch ref.kind {
        case .head: return "Detached HEAD"
        case .localBranch: return ref.isCurrent ? "\(ref.name) (current branch)" : "\(ref.name) (branch)"
        case .remoteBranch: return "\(ref.name) (remote branch)"
        case .tag: return "\(ref.name) (tag)"
        }
    }
}
