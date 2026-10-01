import LumiKit
import SwiftUI

/// Commit satırının üstünde bekleyince açılan kart (Orca'nın konu tooltip'i):
/// tam mesaj (konu + gövde) ve hash · yazar · tarih.
///
/// Ayrı pencere (popover / `.help`) DEĞİL, listenin kendi overlay'idir:
/// popover terminalin klavye odağını çalabilir ve imleç karta geçince satır
/// hover'ını kaybedip titrer. Kart tıklamaları geçirir (`allowsHitTesting`).
struct CommitHoverCard: View {
    let commit: GitCommit

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(commit.message)
                .font(Theme.Typography.ui(.body, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            let body = commit.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                Text(body)
                    .font(Theme.Typography.ui(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(Self.maxBodyLines)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Theme.Spacing.xs) {
                Text(commit.shortHash).font(Theme.Typography.mono(.caption))
                Text("·")
                Text(commit.author).lineLimit(1)
                Text("·")
                Text(commit.date.formatted(date: .abbreviated, time: .shortened))
            }
            .font(Theme.Typography.ui(.caption))
            .foregroundStyle(Theme.textMuted)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: Theme.Graph.hoverCardMaxWidth, alignment: .leading)
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
        )
        .shadow(color: .black.opacity(Self.shadowOpacity), radius: Theme.Spacing.md, y: Theme.Spacing.xxs)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Uzun gövde kartı listeden taşırmasın.
    private static let maxBodyLines = 14
    private static let shadowOpacity = 0.35
}

/// Kartın bağlanacağı satırın sınırları — yalnız kart gösterilen satır yazar.
struct CommitHoverAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// Kartı satırın altına (liste alt yarısındaysa üstüne) yerleştiren overlay.
struct CommitHoverCardOverlay: View {
    let anchor: Anchor<CGRect>?
    let commit: GitCommit?

    var body: some View {
        GeometryReader { proxy in
            if let anchor, let commit {
                let rect = proxy[anchor]
                let placesBelow = rect.midY < proxy.size.height / 2
                CommitHoverCard(commit: commit)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, placesBelow ? rect.maxY + Theme.Spacing.xxs : 0)
                    .padding(.bottom, placesBelow ? 0 : proxy.size.height - rect.minY + Theme.Spacing.xxs)
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: placesBelow ? .topLeading : .bottomLeading
                    )
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }
}
