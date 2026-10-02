import LumiKit
import LumiState
import SwiftUI

/// Orchestrator'ın mesaj alanı (karar 103): ↩ gönderir, ⌥↩ yeni satır.
/// Cevap sürerken gönder butonu Stop'a döner — süreç kesilir, konuşma
/// bir sonraki mesajda kaldığı yerden sürer.
struct OrchestratorComposer: View {
    let store: OrchestratorStore
    @Binding var draft: String
    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.isResponding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .bottom, spacing: Theme.Spacing.md) {
                TextField("Message the orchestrator…", text: $draft, axis: .vertical)
                    .lineLimit(1...8)
                    .font(Theme.Typography.ui(.base))
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.textPrimary)
                    .focused($isFocused)
                    .onSubmit(send)
                    .padding(Theme.Spacing.md)
                    .background(Theme.bgDeep)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
                    )
                actionButton
            }
            Text("↩ send · ⌥↩ new line · esc close")
                .font(Theme.Typography.captionMono)
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.lg)
        .onAppear { isFocused = true }
    }

    @ViewBuilder
    private var actionButton: some View {
        if store.isResponding {
            IconButton(
                systemName: "stop.fill", label: "Stop response",
                size: .body, side: Theme.scaled(32), cornerRadius: Theme.Radius.md, role: .destructive
            ) {
                Task { await store.stopResponse() }
            }
        } else {
            IconButton(
                systemName: "arrow.up", label: "Send message",
                size: .body, side: Theme.scaled(32), cornerRadius: Theme.Radius.md
            ) { send() }
            .disabled(!canSend)
            .foregroundStyle(canSend ? Theme.accentPrimary : Theme.textMuted)
        }
    }

    private func send() {
        guard canSend else { return }
        let text = draft
        draft = ""
        Task { await store.send(text) }
    }
}
