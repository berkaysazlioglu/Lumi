import LumiKit
import SwiftUI

/// Git History'nin tek satırı (Orca `GitHistoryRow` portu): lane kanvası +
/// açılım oku + konu + ref rozetleri. Yazar/tarih satırda DEĞİL — açılımda ve
/// hover kartında durur, satır tek çizgide kalır.
///
/// Sentetik sınır satırları (Incoming/Outgoing Changes) etkileşimsizdir:
/// soluk metin, ok yok, sağ tık yok.
struct GitHistoryRowView: View {
    let row: CommitGraphRow
    let laneCount: Int
    let upstream: String?
    let isExpanded: Bool
    let isHovered: Bool
    let onToggle: () -> Void

    var body: some View {
        if row.isBoundary {
            content.accessibilityElement(children: .combine)
        } else {
            Button(action: onToggle) { content }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel)
        }
    }

    private var content: some View {
        HStack(spacing: Theme.Spacing.xs) {
            CommitGraphLaneCanvas(row: row, laneCount: laneCount, height: Theme.Graph.compactRowHeight)
            if !row.isBoundary {
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.ui(.caption, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(Theme.Motion.quickEase, value: isExpanded)
                    .accessibilityHidden(true)
            }
            Text(row.commit.message)
                .font(Theme.Typography.ui(.body))
                .foregroundStyle(row.isBoundary ? Theme.textSecondary : Theme.textPrimary)
                .lineLimit(1)
            if row.isBoundary {
                Text(row.commit.author)
                    .font(Theme.Typography.ui(.caption))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !row.isBoundary {
                CommitRefBadges(
                    refs: GitRefDisplay.badges(row.commit.references, upstream: upstream),
                    colorIndex: row.nodeColorIndex,
                    refColor: { ref in
                        CommitGraph.refColorIndex(ref, upstream: upstream).map(Theme.Graph.laneColor)
                    }
                )
            }
        }
        .padding(.trailing, Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Theme.Graph.compactRowHeight)
        .background(isHovered && !row.isBoundary ? Theme.bgElevated : Color.clear)
        .contentShape(Rectangle())
    }

    private var accessibilityLabel: String {
        let verb = isExpanded ? "Hide files in commit" : "Show files in commit"
        return "\(verb) \(row.commit.shortHash): \(row.commit.message)"
    }
}
