// LumiMobile/App/MobileChatView.swift
import SwiftUI
import LumiMobileKit
import Foundation

/// Reports the bottom sentinel's minY within the ScrollView's "chatScroll"
/// coordinate space, so the view can tell whether the list is at the bottom.
private struct BottomSentinelKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Native chat view: displays messages derived from the transcript as
/// line-wrapping bubbles (no horizontal scroll). The composer sends free text.
struct MobileChatView: View {
    let model: AppModel
    let sessionId: String

    @StateObject private var keyboard = KeyboardObserver()
    @State private var draft = ""
    @FocusState private var composerFocused: Bool
    @State private var atBottom = true

    // Combined render list (orca): optimistic pending + journal messages +
    // gated streaming bubble → single list, then folded into turns. Streaming
    // is NO LONGER a separate block; it is a synthetic assistant turn inside
    // the list — it persists until the real message arrives (not removed on turn end).
    private var turns: [FoldedTurn] { foldChatMessages(model.chatRenderMessages(sessionId)) }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if turns.isEmpty {
                                // Phase 2.1: a chat session is now opened only for kind=chat
                                // (TerminalSessionView type routing). Empty chat = "no messages
                                // yet" → call-to-action text instead of misleading "loading".
                                Text("Chat is empty — type below to start.")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 40)
                            }
                            ForEach(turns) { turn in
                                MobileChatMessageView(turn: turn).id(turn.id)
                            }
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                                .background(
                                    GeometryReader { g in
                                        Color.clear.preference(
                                            key: BottomSentinelKey.self,
                                            value: g.frame(in: .named("chatScroll")).minY
                                        )
                                    }
                                )
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .coordinateSpace(name: "chatScroll")
                    // WhatsApp-style: reading never needs the keyboard. Dragging the
                    // transcript pulls it down, tapping empty space dismisses it
                    // (buttons inside messages still win their own taps).
                    .scrollDismissesKeyboard(.interactively)
                    .contentShape(Rectangle())
                    .onTapGesture { composerFocused = false }
                    .onPreferenceChange(BottomSentinelKey.self) { minY in
                        atBottom = chatAtBottom(sentinelMinY: minY, viewportHeight: geo.size.height)
                    }
                    .onChange(of: turns.count) { _, _ in
                        if atBottom { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                    }
                    // Also scroll to bottom as streaming text grows (during token stream).
                    .onChange(of: model.gatedStreaming[sessionId]) { _, _ in
                        if atBottom { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !atBottom {
                            Button {
                                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                                atBottom = true
                            } label: {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.title)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(Color.accentColor)
                                    .background(Circle().fill(Color(uiColor: .systemBackground)))
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 16)
                            .padding(.bottom, 12)
                            .accessibilityLabel("Scroll to latest")
                            .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.15), value: atBottom)
                }
                let pending = model.prompts[sessionId]?.last(where: { $0.state == .pending })
                if let status = model.turnStatus[sessionId], status.working {
                    TurnStatusBar(status: status,
                                  isStopping: model.stoppingSessions.contains(sessionId)) {
                        model.requestStop(sessionId)
                    }
                }
                if let pending {
                    MobileChatPromptCard(
                        prompt: pending,
                        maxHeight: geo.size.height * 0.45,
                        onApproval: { optionId in
                            model.respondPrompt(sessionId, itemId: pending.itemId, revision: pending.revision, optionId: optionId)
                        },
                        onQuestion: { selections in
                            model.respondPromptSelections(sessionId, itemId: pending.itemId, revision: pending.revision, selections: selections)
                        }
                    )
                    // Fresh @State for each pending prompt (prevent selection/free-text/sending leaking);
                    // avoids stale selection or a stuck button across consecutive different prompts.
                    .id(pending.itemId)
                }
                composer
            }
        }
        .padding(.bottom, keyboard.height)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.easeOut(duration: 0.25), value: keyboard.height)
        .task(id: sessionId) { model.subscribeChat(sessionId) }
        // No auto-focus on open (not even for an empty chat): the keyboard only
        // appears when the user taps the composer, like WhatsApp.
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                TextField("Message…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                Button {
                    guard !draft.isEmpty else { return }
                    // Write text → settle → send Enter via a SEPARATE path (submitText).
                    // A combined `text\r` in a single write does not submit in the Claude TUI.
                    model.submitText(sessionId, draft)
                    draft = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill").imageScale(.large)
                }
                .disabled(draft.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(uiColor: .systemBackground))
        }
    }
}
