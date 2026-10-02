import LumiKit
import LumiState
import SwiftUI

/// Orchestrator popup'ı (karar 103): pencerenin %80'ini kaplayan modal sohbet.
///
/// Kapatmak (Escape, dışarı tık, ✕, ⌘J) yalnız GİZLER — orchestrator süreci
/// ve sohbet yaşamaya devam eder. Açılış süreci tembel başlatır.
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
                        OrchestratorTranscriptView(store: shell.orchestrator)
                        divider
                        OrchestratorComposer(store: shell.orchestrator, draft: $draft)
                    }
                }
                .frame(
                    width: proxy.size.width * Self.windowRatio,
                    height: proxy.size.height * Self.windowRatio
                )
            }
        }
        .task { await shell.orchestrator.activate() }
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
