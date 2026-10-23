// LumiMobile/App/MobileChatView.swift
import SwiftUI
import LumiMobileKit
import Foundation

/// Reports the bottom sentinel's minY within the ScrollView's "chatScroll"
/// coordinate space, so the view can tell whether the list is at the bottom.
/// nil when the lazy list has unloaded the sentinel (scrolled far up).
private struct BottomSentinelKey: PreferenceKey {
    static var defaultValue: CGFloat? { nil }
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

/// The chat ScrollView's own height (the sentinel's distance is measured against it).
private struct ViewportHeightKey: PreferenceKey {
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
    @Environment(\.tuiStyle) private var style
    @State private var draft = ""
    @FocusState private var composerFocused: Bool
    /// Decision 131: auto-follow — the chat stays on the latest output until the user
    /// scrolls up past `followPolicy.threshold`.
    @State private var isFollowing = true
    @State private var isScrolledUp = false
    @State private var showsJumpButton = false
    @State private var scrollHandle = ChatScrollHandle()
    /// Opening a chat lands on the latest message (WhatsApp-style). Cleared once
    /// the first non-empty history has been scrolled to the bottom.
    @State private var needsInitialScroll = true
    /// Decision 131: the prompt the sticky header names (nil → no header).
    @State private var stickyPromptId: String?
    /// Decision 131: turn count when the user left the bottom (jump button's count).
    @State private var countWhenLeft: Int?
    /// Decision 131: the first turn before "Load earlier messages" — kept in view.
    @State private var earlierAnchorId: String?

    /// Height the sticky header covers; a prompt under it counts as scrolled above.
    private static let stickyHeaderHeight: CGFloat = 32
    /// Lines the user may drift from the bottom before the jump button shows.
    private static let jumpThresholdLines: CGFloat = 3

    private var followPolicy: ChatFollowPolicy {
        ChatFollowPolicy(threshold: style.font().lineHeight * Self.jumpThresholdLines)
    }

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
                        LazyVStack(alignment: .leading, spacing: style.font().lineHeight) {
                            if turns.isEmpty {
                                // Phase 2.1: a chat session is now opened only for kind=chat
                                // (TerminalSessionView type routing). Decision 130: "empty" only
                                // once the Mac's snapshot said so; before that it is still loading.
                                Text(isSyncing ? "Loading chat…" : "Chat is empty — type below to start.")
                                    .font(style.swiftUIFont)
                                    .foregroundStyle(LumiPalette.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 40)
                            }
                            if model.chatHasEarlier.contains(sessionId) && !turns.isEmpty {
                                // Decision 130/131: the list starts at the cache's or the Mac
                                // frame's cut — the Mac may still send the rest.
                                let requested = model.fullChatRequested.contains(sessionId)
                                ChatEarlierMessagesRow(canLoad: !requested, isLoading: requested && isSyncing) {
                                    earlierAnchorId = turns.first?.id
                                    model.loadEarlierChat(sessionId)
                                }
                            }
                            ForEach(turns) { turn in
                                MobileChatMessageView(turn: turn)
                                    .id(turn.id)
                                    .reportsChatTurnFrame(turn.id)
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
                        .background(ChatScrollViewFinder(handle: scrollHandle))
                    }
                    .coordinateSpace(name: "chatScroll")
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: ViewportHeightKey.self, value: g.size.height)
                        }
                    )
                    .background(LumiPalette.background)
                    // WhatsApp-style: reading never needs the keyboard. Dragging the
                    // transcript pulls it down, tapping empty space dismisses it
                    // (buttons inside messages still win their own taps).
                    .scrollDismissesKeyboard(.interactively)
                    .contentShape(Rectangle())
                    .onTapGesture { composerFocused = false }
                    .onPreferenceChange(BottomSentinelKey.self) { minY in
                        scrollHandle.sentinelMinY = minY
                        scrollMoved(proxy)
                    }
                    .onPreferenceChange(ViewportHeightKey.self) { height in
                        scrollHandle.viewportHeight = height
                        scrollMoved(proxy)
                    }
                    .onPreferenceChange(ChatTurnFramesKey.self) { frames in
                        let id = chatStickyPromptId(turns: turns, frames: frames,
                                                    topInset: Self.stickyHeaderHeight)
                        if id != stickyPromptId { stickyPromptId = id }
                    }
                    .onChange(of: isFollowing) { _, following in
                        countWhenLeft = following ? nil : turns.count
                    }
                    // Decision 131: earlier messages landed above — stay on what was on screen,
                    // and do not count them as new.
                    .onChange(of: isSyncing) { _, syncing in
                        guard !syncing, let anchor = earlierAnchorId else { return }
                        earlierAnchorId = nil
                        if countWhenLeft != nil { countWhenLeft = turns.count }
                        proxy.scrollTo(anchor, anchor: .top)
                    }
                    // History already cached when the chat reopens → no count change fires.
                    .onAppear { scrollToLatestIfNeeded(proxy) }
                    // New turns, streaming text and growing tool output all move the
                    // sentinel; `scrollMoved` re-pins a following chat (decision 131).
                    .onChange(of: turns.count) { _, _ in
                        if needsInitialScroll { scrollToLatestIfNeeded(proxy) }
                    }
                    .overlay(alignment: .bottom) {
                        if showsJumpButton {
                            ChatJumpToBottomButton(
                                newCount: chatNewTurnCount(current: turns.count, countWhenLeft: countWhenLeft)
                            ) {
                                jumpToBottom(proxy)
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.15), value: showsJumpButton)
                    .overlay(alignment: .top) {
                        VStack(spacing: 0) {
                            if isScrolledUp, let id = stickyPromptId, let text = promptText(id) {
                                ChatStickyPromptHeader(text: text) {
                                    jumpToPrompt(id, proxy)
                                }
                            }
                            if isSyncing && !turns.isEmpty { syncingBadge }
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: isSyncing)
                    .animation(.easeInOut(duration: 0.15), value: stickyPromptId)
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
                        draft: model.promptDraft(sessionId, itemId: pending.itemId),
                        onDraftChange: { model.updatePromptDraft(sessionId, itemId: pending.itemId, $0) },
                        onApproval: { optionId in
                            model.respondPrompt(sessionId, itemId: pending.itemId, revision: pending.revision, optionId: optionId)
                        },
                        onQuestion: { selections in
                            model.respondPromptSelections(sessionId, itemId: pending.itemId, revision: pending.revision, selections: selections)
                        }
                    )
                    // Fresh `sending` @State for each pending prompt (selection draft lives in
                    // AppModel.promptDrafts, keyed by itemId, so it survives this reset).
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

    /// First non-empty render lands on the latest message: scrolls unconditionally,
    /// then once more after the selectable text views have sized themselves (a
    /// following chat is also re-pinned by `scrollMoved` as the lazy list settles).
    private func scrollToLatestIfNeeded(_ proxy: ScrollViewProxy) {
        guard needsInitialScroll, !turns.isEmpty else { return }
        needsInitialScroll = false
        isFollowing = true
        proxy.scrollTo("bottom", anchor: .bottom)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    /// Decision 131: one geometry update (sentinel or viewport). Only the derived flags
    /// are state, and each is written only when it changes.
    private func scrollMoved(_ proxy: ScrollViewProxy) {
        let distance = chatDistanceFromBottom(sentinelMinY: scrollHandle.sentinelMinY,
                                              viewportHeight: scrollHandle.viewportHeight)
        let policy = followPolicy
        let step = policy.step(distance: distance, isFollowing: isFollowing,
                               isUserScrolling: scrollHandle.isUserScrolling)
        if step.isFollowing != isFollowing { isFollowing = step.isFollowing }
        if step.isScrolledUp != isScrolledUp { isScrolledUp = step.isScrolledUp }
        let jump = policy.showsJumpButton(distance: distance, isFollowing: step.isFollowing)
        if jump != showsJumpButton { showsJumpButton = jump }
        // Outside the preference pass: scrolling here re-enters layout.
        if step.shouldScrollToBottom { DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) } }
    }

    /// Mid-fling a `scrollTo` loses to the deceleration — stop it first. Following
    /// again lets `scrollMoved` keep re-pinning until the lazy list has settled.
    private func jumpToBottom(_ proxy: ScrollViewProxy) {
        scrollHandle.stopMomentum()
        isFollowing = true
        isScrolledUp = false
        showsJumpButton = false
        proxy.scrollTo("bottom", anchor: .bottom)
    }

    /// The header's prompt: cancel any fling, pause following (so the jump up is not
    /// re-pinned), then scroll.
    private func jumpToPrompt(_ id: String, _ proxy: ScrollViewProxy) {
        scrollHandle.stopMomentum()
        isFollowing = false
        withAnimation { proxy.scrollTo(id, anchor: .top) }
    }

    /// Decision 131: the sticky header's text — the prompt's own words.
    private func promptText(_ id: String) -> String? {
        guard let turn = turns.first(where: { $0.id == id }) else { return nil }
        for case let .user(text) in tuiItems(for: turn) { return text }
        return nil
    }

    /// Decision 130: shown over the cached messages while the Mac re-sends the chat.
    private var isSyncing: Bool { model.chatSyncing.contains(sessionId) && model.macOnline }

    private var syncingBadge: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text("Syncing…").font(.caption)
        }
        .foregroundStyle(LumiPalette.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(LumiPalette.elevated, in: Capsule())
        .padding(.top, 6)
        .transition(.opacity)
        .accessibilityLabel("Syncing chat")
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                TextField("Message…", text: $draft, axis: .vertical)
                    .font(style.swiftUIFont)
                    .lumiField()
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
            .background(LumiPalette.background)
        }
    }
}
