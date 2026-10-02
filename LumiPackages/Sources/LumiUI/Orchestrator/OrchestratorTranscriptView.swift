import LumiKit
import LumiState
import SwiftUI

/// Orchestrator sohbetinin mesaj listesi (karar 103). Yeni mesaj ya da akan
/// metin geldikçe en alta kayar.
struct OrchestratorTranscriptView: View {
    let store: OrchestratorStore

    private static let bottomAnchor = "orchestrator.bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if store.messages.isEmpty, store.pendingPrompt == nil {
                        OrchestratorEmptyState()
                    }
                    ForEach(store.messages) { message in
                        OrchestratorMessageRow(message: message)
                    }
                    if let pending = store.pendingPrompt {
                        OrchestratorUserBubble(text: pending, isPending: true)
                    }
                    if let streaming = store.streamingText, !streaming.isEmpty {
                        OrchestratorAssistantText(text: streaming)
                    } else if store.isResponding {
                        OrchestratorThinkingRow()
                    }
                    if let error = store.errorMessage {
                        OrchestratorErrorRow(text: error)
                    }
                    Color.clear.frame(height: Theme.Spacing.xxs).id(Self.bottomAnchor)
                }
                .padding(.horizontal, Theme.Spacing.xxl)
                .padding(.vertical, Theme.Spacing.xl)
            }
            .onChange(of: store.messages.count) { scrollToBottom(proxy) }
            .onChange(of: store.streamingText) { scrollToBottom(proxy) }
            .onChange(of: store.pendingPrompt) { scrollToBottom(proxy) }
            .onAppear { scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
    }
}

/// Tek mesaj: kullanıcı metni balon, asistan metni düz yazı, araç
/// çağrıları/sonuçları tek satırlık sessiz kayıt.
struct OrchestratorMessageRow: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(Array(message.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `mcp__lumi__list_terminals` → `list_terminals` (Lumi'nin kendi araçları).
    static func displayName(_ toolName: String) -> String {
        let prefix = OrchestratorTools.allowRule + "__"
        return toolName.hasPrefix(prefix) ? String(toolName.dropFirst(prefix.count)) : toolName
    }

    @ViewBuilder
    private func blockView(_ block: ChatBlock) -> some View {
        switch block {
        case let .text(text, _):
            if message.role == .user {
                // Faz 4: mesaja iliştirilen `<lumi-activity>` notu kullanıcının yazdığı değildir.
                let visible = OrchestratorActivityNote.strip(text)
                if !visible.isEmpty { OrchestratorUserBubble(text: visible, isPending: false) }
            } else {
                OrchestratorAssistantText(text: text)
            }
        case let .toolCall(name, preview, _):
            OrchestratorToolLine(icon: "chevron.right", text: "\(Self.displayName(name)) \(preview)", isError: false)
        case let .toolResult(output, isError):
            OrchestratorToolLine(icon: "arrow.turn.down.right", text: output, isError: isError)
        case .imageRef, .subagentGroup, .unknown:
            EmptyView()
        }
    }
}

struct OrchestratorUserBubble: View {
    let text: String
    let isPending: Bool

    private static var maxBubbleWidth: CGFloat { Theme.scaled(560) }

    var body: some View {
        HStack {
            Spacer(minLength: Theme.Spacing.xxxl)
            Text(text)
                .font(Theme.Typography.ui(.base))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.accentDeep.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                .frame(maxWidth: Self.maxBubbleWidth, alignment: .trailing)
                .opacity(isPending ? 0.6 : 1)
        }
    }
}

/// Asistan metni — satır içi markdown (kalın, kod, link) satır sonları korunarak.
struct OrchestratorAssistantText: View {
    let text: String

    var body: some View {
        Text(Self.rendered(text))
            .font(Theme.Typography.ui(.base))
            .foregroundStyle(Theme.textPrimary)
            .textSelection(.enabled)
            .lineSpacing(Theme.Spacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func rendered(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

struct OrchestratorToolLine: View {
    let icon: String
    let text: String
    let isError: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.Typography.ui(.caption, weight: .semibold))
            Text(text)
                .font(Theme.Typography.captionMono)
                .lineLimit(3)
                .truncationMode(.tail)
                .textSelection(.enabled)
        }
        .foregroundStyle(isError ? Theme.error : Theme.textMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OrchestratorThinkingRow: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ProgressView().controlSize(.small)
            Text("Thinking…")
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textMuted)
        }
    }
}

struct OrchestratorErrorRow: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(Theme.Typography.labelMono)
            .foregroundStyle(Theme.error)
    }
}

/// Boş konuşma: orchestrator'ın ne işe yaradığını anlatan kısa giriş.
struct OrchestratorEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Talk to all your agents from one place.")
                .font(Theme.Typography.mono(.title, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Ask what each terminal is doing, relay a message to a chat or start a new agent. "
                + "The orchestrator runs its own Claude with Lumi's system prompt — no project settings are loaded.")
                .font(Theme.Typography.ui(.body))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Spacing.xl)
    }
}
