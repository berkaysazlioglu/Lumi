import LumiKit
import LumiState
import SwiftUI

/// Popup'ın sağ sütunu (karar 103 Faz 4): ajan terminallerinden gelen
/// "bitti / soru soruyor / karar bekliyor / hata" kartları, en yeni üstte.
/// Kartlar model turu açmaz; kullanıcının bir sonraki mesajına not olarak
/// iliştirilir.
struct OrchestratorActivityPanel: View {
    let feed: OrchestratorActivityFeed
    /// Terminal hâlâ açık mı (Open düğmesi için).
    let isOpen: (TerminalID) -> Bool
    let onOpen: (OrchestratorEvent) -> Void
    let onReply: (OrchestratorEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ACTIVITY")
                    .font(Theme.Typography.ui(.caption, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            if feed.events.isEmpty {
                Text("Finished turns, questions and errors from your agents appear here.")
                    .font(Theme.Typography.ui(.body))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, Theme.Spacing.lg)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.md) {
                        ForEach(feed.events) { event in
                            OrchestratorActivityCard(
                                event: event,
                                canOpen: isOpen(event.terminalID),
                                onOpen: { onOpen(event) },
                                onReply: { onReply(event) },
                                onDismiss: { feed.dismiss(event.id) }
                            )
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.lg)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.bgDeep.opacity(0.4))
    }
}

struct OrchestratorActivityCard: View {
    let event: OrchestratorEvent
    let canOpen: Bool
    let onOpen: () -> Void
    let onReply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Image(systemName: style.icon)
                    .font(Theme.Typography.ui(.label, weight: .semibold))
                    .foregroundStyle(style.color)
                Text(event.terminalTitle)
                    .font(Theme.Typography.mono(.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Theme.Spacing.xs)
                IconButton(systemName: "xmark", label: "Dismiss", size: .caption, action: onDismiss)
            }
            HStack(spacing: Theme.Spacing.xs) {
                Text(style.label)
                    .foregroundStyle(style.color)
                Text("·")
                Text(event.at, style: .relative)
            }
            .font(Theme.Typography.captionMono)
            .foregroundStyle(Theme.textMuted)
            Text(event.location)
                .font(Theme.Typography.captionMono)
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(OrchestratorAssistantText.rendered(event.summary))
                .font(Theme.Typography.ui(.body))
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Theme.Spacing.md) {
                linkButton("Open", systemImage: "arrow.up.forward.square", action: onOpen)
                    .disabled(!canOpen)
                    .opacity(canOpen ? 1 : 0.4)
                linkButton("Reply", systemImage: "arrowshape.turn.up.left", action: onReply)
                Spacer()
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(event.needsUser ? Theme.warning.opacity(0.6) : Theme.border, lineWidth: Theme.Stroke.hairline)
        )
    }

    private func linkButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        HoverReader { isHovering in
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .font(Theme.Typography.ui(.label, weight: .medium))
                    .foregroundStyle(isHovering ? Theme.textPrimary : Theme.accentPrimary)
            }
            .buttonStyle(.plain)
        }
    }

    private var style: (icon: String, color: Color, label: String) {
        switch event.kind {
        case .finished where event.needsUser:
            return ("questionmark.circle.fill", Theme.warning, "asks you")
        case .finished:
            return ("checkmark.circle.fill", Theme.success, "finished")
        case .needsDecision:
            return ("hand.raised.fill", Theme.warning, "awaiting decision")
        case .failed:
            return ("exclamationmark.triangle.fill", Theme.error, "error")
        }
    }
}

#if DEBUG
#Preview("Activity") {
    let feed = OrchestratorActivityFeed()
    feed.append(OrchestratorEvent(
        terminalID: TerminalID(), terminalTitle: "api-refactor", location: "api · main",
        kind: .finished, summary: "Auth testlerini düzeltti, 3 dosya değişti. Commit atayım mı diye soruyor.",
        needsUser: true, at: Date().addingTimeInterval(-120)
    ))
    feed.append(OrchestratorEvent(
        terminalID: TerminalID(), terminalTitle: "ios-fix", location: "ios · ios-wt · fix/crash",
        kind: .finished, summary: "Crash'i giderdi, build yeşil.", needsUser: false, at: Date()
    ))
    return OrchestratorActivityPanel(feed: feed, isOpen: { _ in true }, onOpen: { _ in }, onReply: { _ in })
        .frame(width: 320, height: 520)
}
#endif
