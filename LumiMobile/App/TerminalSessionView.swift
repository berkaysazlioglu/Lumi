import SwiftUI
import LumiMobileKit

/// Full-screen terminal view for a single Claude Code session.
/// Renders raw PTY bytes via SwiftTerm and forwards user input back to the Mac.
///
/// Accessory key bar (modifier keys, arrow cluster, etc.) is deferred to Task 10.
struct TerminalSessionView: View {
    let model: AppModel
    let sessionId: String

    /// Reference-type buffer that accumulates chunks until the view is ready to attach
    /// and drains them immediately on attach (bug #3: the old `@State` view handshake
    /// never delivered the chunks).
    @State private var buffer = TerminalFeedBuffer()
    /// Tracks keyboard height; manually shifts the bottom bar above the keyboard (bug #1).
    @StateObject private var keyboard = KeyboardObserver()
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        // Phase 2.1: the view is chosen based on the session TYPE (reactive — `isChatSession`
        // checks `chatSessionIds`/`sessions`). Chat session → chat view; terminal
        // session → mirror. The old `showChat=true` default was opening terminal sessions
        // in a dead chat mode and leaving them stuck on "loading" (regression). After
        // stream-json there is no longer a single alternative view valid for both types,
        // so the manual toggle was removed.
        Group {
            if model.isChatSession(sessionId) {
                MobileChatView(model: model, sessionId: sessionId)
            } else {
                terminalBody
            }
        }
        .onDisappear { model.unsubscribe(sessionId) }
        .navigationTitle(model.session(sessionId)?.repoName ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { toolbarItems }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete this chat", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Delete this chat?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                // Pop back to home first, then end the session on the Mac.
                dismiss()
                Task { await model.deleteSession(sessionId: sessionId) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This session will be ended on the Mac.")
        }
    }

    /// Current terminal-mirror body (VStack + keyboard padding + .task subscribe/feed).
    private var terminalBody: some View {
        VStack(spacing: 0) {
            TerminalHostView(onInput: { model.sendInput(sessionId, $0) }, buffer: buffer)
            AccessoryBar(sendInput: { model.sendInput(sessionId, $0) },
                         submitText: { model.submitText(sessionId, $0) })
        }
        // Disable automatic keyboard avoidance; apply the height manually → the bar stays
        // above the keyboard at all times, and the terminal stays above the bar.
        .padding(.bottom, keyboard.height)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.easeOut(duration: 0.25), value: keyboard.height)
        .task(id: sessionId) {
            model.subscribe(sessionId)
            for await chunk in model.terminalStream(sessionId) {
                buffer.feed(chunk)
            }
        }
        .onDisappear {
            buffer.detach()
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarItems: some View {
        HStack(spacing: 12) {
            // Status badge
            if let meta = model.session(sessionId) {
                StatusBadge(badge: meta.badge)
            }

            // Model picker menu
            if let meta = model.session(sessionId) {
                modelMenu(for: meta)
            }
        }
    }

    @ViewBuilder
    private func modelMenu(for meta: SessionMeta) -> some View {
        let currentModel = model.currentModel(for: sessionId)
        let label = currentModel.map { model.modelLabel($0) } ?? "Model"
        Menu {
            Button("Haiku") {
                Task { await model.setModel(sessionId: sessionId, model: "claude-haiku-4-5") }
            }
            Button("Sonnet") {
                Task { await model.setModel(sessionId: sessionId, model: "claude-sonnet-4-5") }
            }
            Button("Opus") {
                Task { await model.setModel(sessionId: sessionId, model: "claude-opus-4-5") }
            }
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.accentColor)
        }
    }
}
