import LumiKit
import LumiState
import SwiftUI

/// Orchestrator popup'ı (karar 103): pencerenin %80'ini kaplayan modal sohbet.
///
/// Kapatmak (Escape, dışarı tık, ✕, ⌘J) yalnız GİZLER — orchestrator süreci
/// ve sohbet yaşamaya devam eder. Açılış süreci tembel başlatır. Sağ sütun
/// ajanlardan gelen Activity kartlarıdır (Faz 4).
public struct OrchestratorOverlay: View {
    @Shell private var shell
    @State private var draft = ""

    public init() {}

    /// Popup'ın pencereye oranı (her iki eksende).
    private static var windowRatio: CGFloat { 0.8 }

    public var body: some View {
        GeometryReader { proxy in
            ModalOverlay(onDismiss: dismiss) {
                Panel(variant: .modal) {
                    VStack(spacing: 0) {
                        OrchestratorHeader(store: shell.orchestrator, onClose: dismiss)
                        divider
                        HStack(spacing: 0) {
                            VStack(spacing: 0) {
                                OrchestratorTranscriptView(store: shell.orchestrator)
                                OrchestratorApprovalList(approvals: shell.orchestrator.approvals)
                                divider
                                OrchestratorComposer(store: shell.orchestrator, draft: $draft)
                            }
                            Rectangle().fill(Theme.border).frame(width: Theme.Stroke.hairline)
                            OrchestratorActivityPanel(
                                feed: shell.orchestrator.activity,
                                watched: watchedTerminals,
                                onFocus: focus,
                                onUnwatch: { shell.orchestrator.watchList.unwatch($0) },
                                isOpen: { shell.terminals.meta(for: $0) != nil },
                                onOpen: open,
                                onReply: reply
                            )
                            .frame(width: Self.activityWidth)
                        }
                    }
                }
                .frame(
                    width: proxy.size.width * Self.windowRatio,
                    height: proxy.size.height * Self.windowRatio
                )
            }
        }
        .task { await shell.orchestrator.activate() }
        // Faz 4: popup açıkken gelen olaylar görülmüş sayılır (top bar noktası).
        .onAppear { shell.orchestrator.activity.markAllRead() }
        .onChange(of: shell.orchestrator.activity.unreadCount) { _, count in
            if count > 0 { shell.orchestrator.activity.markAllRead() }
        }
    }

    private static var activityWidth: CGFloat { Theme.scaled(320) }

    /// İzlenen canlı terminaller, terminal listesinin sırasıyla.
    private var watchedTerminals: [TerminalMeta] {
        shell.terminals.terminals.filter { shell.orchestrator.watchList.isWatched($0) }
    }

    /// Terminali grid'de öne getirir; popup kapanır ki terminal görülsün.
    private func open(_ event: OrchestratorEvent) {
        guard let meta = shell.terminals.meta(for: event.terminalID) else { return }
        focus(meta)
    }

    private func focus(_ meta: TerminalMeta) {
        dismiss()
        shell.focusAgent(meta)
    }

    /// Composer'ı o terminale yanıt için hazırlar — orchestrator `send_to_terminal`'a çevirir.
    private func reply(_ event: OrchestratorEvent) {
        draft = "Reply to “\(event.terminalTitle)”: "
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
    }

    private func dismiss() {
        shell.dialogs.isOrchestratorOpen = false
    }
}

/// Başlık: ad + süreç durumu, yeni konuşma ve kapatma.
struct OrchestratorHeader: View {
    let store: OrchestratorStore
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: OrchestratorToolbarItem.iconName)
                .font(Theme.Typography.ui(.title, weight: .semibold))
                .foregroundStyle(Theme.accentPrimary)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Orchestrator")
                    .font(Theme.Typography.mono(.headline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: Theme.Spacing.xs) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: Theme.Spacing.sm, height: Theme.Spacing.sm)
                    Text(statusText)
                        .font(Theme.Typography.labelMono)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            Spacer()
            IconButton(
                systemName: "square.and.pencil", label: "New conversation",
                size: .body, weight: .regular,
                side: Theme.scaled(28), cornerRadius: Theme.Radius.md
            ) {
                Task { await store.newConversation() }
            }
            .disabled(store.phase == .starting)
            IconButton(
                systemName: "xmark", label: "Close orchestrator",
                side: Theme.scaled(28), cornerRadius: Theme.Radius.md, action: onClose
            )
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    private var statusText: String {
        switch store.phase {
        case .starting: return "Starting…"
        case .idle: return "Not running — sending a message resumes the conversation"
        case .running: return store.isResponding ? "Responding…" : "Ready"
        }
    }

    private var statusColor: Color {
        switch store.phase {
        case .starting: return Theme.warning
        case .idle: return Theme.textMuted
        case .running: return store.isResponding ? Theme.accentCyan : Theme.success
        }
    }
}

#if DEBUG
#Preview("Orchestrator") {
    OrchestratorOverlay()
        .frame(width: 1100, height: 760)
        .environment(\.shell, ShellContext.preview())
}
#endif
