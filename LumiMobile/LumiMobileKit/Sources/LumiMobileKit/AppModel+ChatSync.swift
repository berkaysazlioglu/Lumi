import Foundation
import LumiWire

/// Decision 130: chat sync lifecycle — a (re)subscribe never wipes what the phone
/// already shows; it marks the chat "syncing" until the Mac's snapshot arrives,
/// retries a lost subscribe, and leaving a chat releases the Mac tail lazily.
extension AppModel {
    /// Sends a mode=chat subscribe and arms the retry watchdog.
    func sendChatSubscribe(_ sessionId: String, attempt: Int = 1) {
        chatSyncing.insert(sessionId)
        syncGaveUp.remove(sessionId)
        let frame = PhoneProtocol.subscribeFrame(sessionId: sessionId, mode: "chat",
                                                 afterId: syncCursor(sessionId))
        Task { await client.send(frame: frame) }
        syncWatchdogs[sessionId]?.cancel()
        let timeout = chatSyncTimeout
        syncWatchdogs[sessionId] = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.chatSyncTimedOut(sessionId, attempt: attempt)
        }
    }

    /// The snapshot did not arrive in time. While disconnected the reconnect path
    /// re-subscribes, so only a live connection spends an attempt.
    private func chatSyncTimedOut(_ sessionId: String, attempt: Int) {
        syncWatchdogs[sessionId] = nil
        guard chatSyncing.contains(sessionId), activeSessionId == sessionId, activeChatMode,
              connection == .connected else { return }
        guard attempt < chatSyncMaxAttempts else {
            DiagLog.shared.log("model", "chat sync gave up sid=\(sessionId.prefix(8))")
            chatSyncing.remove(sessionId)
            syncGaveUp.insert(sessionId)
            return
        }
        DiagLog.shared.log("model", "chat sync retry sid=\(sessionId.prefix(8)) attempt=\(attempt + 1)")
        sendChatSubscribe(sessionId, attempt: attempt + 1)
    }

    /// Last message the phone holds, if its id is stable across Mac reads — `idx-N`
    /// fallbacks are line positions and could match a different transcript.
    func syncCursor(_ sessionId: String) -> String? {
        guard let id = chatBySession[sessionId]?.last?.id, !id.hasPrefix("idx-") else { return nil }
        return id
    }

    /// A `chat_append` carrying `afterId` answers a delta subscribe: the Mac's rows after
    /// `afterId`, so they replace whatever the list holds past it. It applies only to a
    /// list that holds `afterId` — its prefix is contiguous because plain appends never
    /// land on a list that is not live. Another phone's reply, or one for a list replaced
    /// meanwhile, is ignored (nil) — no automatic resubscribe, so phones never ping-pong.
    func deltaReplyList(_ sessionId: String, afterId: String, messages: [ChatMessage]) -> [ChatMessage]? {
        guard let current = chatBySession[sessionId],
              let anchor = current.firstIndex(where: { $0.id == afterId }) else {
            DiagLog.shared.log("model", "delta reply ignored sid=\(sessionId.prefix(8)) afterId=\(afterId.prefix(8))")
            return nil
        }
        finishChatSync(sessionId)
        liveChats.insert(sessionId)
        return Array(current[...anchor]) + messages
    }

    /// A plain `chat_append` upserts by id, but only into a live list. Without an anchor
    /// (no snapshot yet — e.g. the tail of a subscribe made by an earlier app run, or
    /// rows after a disconnect) it is dropped (nil): kept, it would make the list look
    /// complete to the next delta subscribe and hide everything before it.
    func liveAppendList(_ sessionId: String, messages: [ChatMessage]) -> [ChatMessage]? {
        guard liveChats.contains(sessionId) else {
            if !messages.isEmpty {
                DiagLog.shared.log("model", "append ignored (not live) sid=\(sessionId.prefix(8)) count=\(messages.count)")
            }
            return nil
        }
        var current = chatBySession[sessionId] ?? []
        for message in messages {
            if let idx = current.firstIndex(where: { $0.id == message.id }) {
                current[idx] = message
            } else {
                current.append(message)
            }
        }
        return current
    }

    /// The Mac answered the subscribe (or the session went away).
    func finishChatSync(_ sessionId: String) {
        chatSyncing.remove(sessionId)
        syncGaveUp.remove(sessionId)
        syncWatchdogs[sessionId]?.cancel()
        syncWatchdogs[sessionId] = nil
    }

    /// The session screen went away. Terminal mirrors unsubscribe at once; chats drop
    /// their selection now but keep the Mac tail for `chatReleaseDelay`, so a quick
    /// return only re-syncs (messages keep flowing into the cache meanwhile).
    public func leaveSession(_ sessionId: String) {
        guard isChatSession(sessionId) else {
            unsubscribe(sessionId)
            return
        }
        if activeSessionId == sessionId {
            activeSessionId = nil
            activeChatMode = false
        }
        finishChatSync(sessionId)
        pendingReleases[sessionId]?.cancel()
        let delay = chatReleaseDelay
        pendingReleases[sessionId] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.pendingReleases[sessionId] = nil
            // Re-entered meanwhile → subscribeChat cancelled this; double-check anyway.
            guard self.activeSessionId != sessionId else { return }
            self.unsubscribe(sessionId)
        }
    }

    func cancelPendingRelease(_ sessionId: String) {
        pendingReleases[sessionId]?.cancel()
        pendingReleases[sessionId] = nil
    }

    /// The app came to the foreground: the socket may have died in the background.
    public func appBecameActive() async {
        await client.reconnectIfStale()
    }
}
