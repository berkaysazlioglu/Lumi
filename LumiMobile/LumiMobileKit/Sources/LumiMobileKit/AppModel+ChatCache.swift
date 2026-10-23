import Foundation
import LumiWire

/// Decision 130 (phase 3): the chat cache. The Mac stays the source of truth — a
/// `chat` snapshot still REPLACES the list (decision 94's `/clear` wipe relies on
/// it); the cache only fills the gap until that snapshot arrives.
extension AppModel {
    /// Cold start: show the cached chat while the subscribe is in flight.
    func restoreCachedChatIfNeeded(_ sessionId: String) {
        guard chatBySession[sessionId] == nil else { return }
        guard let entry = chatCache.load(sessionId) else {
            chatBySession[sessionId] = []
            return
        }
        DiagLog.shared.log("cache", "chat restored sid=\(sessionId.prefix(8)) count=\(entry.messages.count)")
        chatBySession[sessionId] = entry.messages
        if entry.hasEarlier { chatHasEarlier.insert(sessionId) }
    }

    /// Coalesces bursts of appends (a live turn appends every ~0.5 s) into one write.
    func scheduleChatCacheSave(_ sessionId: String) {
        cacheSaves[sessionId]?.cancel()
        let delay = chatCacheDelay
        cacheSaves[sessionId] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.writeChatCache(sessionId)
        }
    }

    /// Writes every pending chat now (app going to the background).
    public func flushChatCache() {
        let pending = Array(cacheSaves.keys)
        for sessionId in pending { writeChatCache(sessionId) }
    }

    private func writeChatCache(_ sessionId: String) {
        cacheSaves[sessionId]?.cancel()
        cacheSaves[sessionId] = nil
        guard let messages = chatBySession[sessionId] else { return }
        chatCache.save(sessionId, entry: ChatCacheEntry(
            messages: messages, hasEarlier: chatHasEarlier.contains(sessionId)))
    }
}
