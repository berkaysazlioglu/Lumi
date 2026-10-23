import Foundation
import LumiWire

/// Decision 130: the last messages of a chat, kept on disk so a cold start shows
/// the conversation at once while the Mac re-sends it.
public struct ChatCacheEntry: Sendable, Equatable {
    public let messages: [ChatMessage]
    /// Older rows exist beyond these (Mac frame cap or the cache's own cap).
    public let hasEarlier: Bool

    public init(messages: [ChatMessage], hasEarlier: Bool) {
        self.messages = messages
        self.hasEarlier = hasEarlier
    }
}

public protocol ChatCaching: Sendable {
    func load(_ sessionId: String) -> ChatCacheEntry?
    func save(_ sessionId: String, entry: ChatCacheEntry)
    func remove(_ sessionId: String)
    /// Drops every cached chat whose session is not in `keeping`.
    func prune(keeping: Set<String>)
    func clear()
}

/// No persistence (tests, demo mode).
public struct NoChatCache: ChatCaching {
    public init() {}
    public func load(_ sessionId: String) -> ChatCacheEntry? { nil }
    public func save(_ sessionId: String, entry: ChatCacheEntry) {}
    public func remove(_ sessionId: String) {}
    public func prune(keeping: Set<String>) {}
    public func clear() {}
}

/// One JSON file per session under Caches/chat-cache. Writes run on a serial queue;
/// a load waits for queued writes so it never reads a half-written file.
public final class FileChatCache: ChatCaching, @unchecked Sendable {
    /// Newest messages kept per chat.
    public static let maxMessages = 200
    /// 2: build 495 could cache a list built from unanchored appends (no history before
    /// them); bumping drops those files once, and the next subscribe fetches in full.
    private static let formatVersion = 2

    private let directory: URL
    private let queue = DispatchQueue(label: "com.lumi.mobile.chat-cache", qos: .utility)

    public init(directory: URL) {
        self.directory = directory
    }

    public static func standard() -> FileChatCache {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return FileChatCache(directory: caches.appendingPathComponent("chat-cache", isDirectory: true))
    }

    public func load(_ sessionId: String) -> ChatCacheEntry? {
        guard let url = fileURL(sessionId) else { return nil }
        return queue.sync {
            guard let data = try? Data(contentsOf: url) else { return nil }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["v"] as? Int == Self.formatVersion,
                  let raw = object["messages"] as? [[String: Any]] else {
                DiagLog.shared.log("cache", "unreadable chat cache sid=\(sessionId.prefix(8)) → dropped")
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return ChatCacheEntry(messages: raw.compactMap(ChatMessage.decode),
                                  hasEarlier: object["hasEarlier"] as? Bool ?? false)
        }
    }

    public func save(_ sessionId: String, entry: ChatCacheEntry) {
        guard let url = fileURL(sessionId) else { return }
        let kept = entry.messages.suffix(Self.maxMessages)
        let object: [String: Any] = [
            "v": Self.formatVersion,
            "hasEarlier": entry.hasEarlier || kept.count < entry.messages.count,
            "messages": kept.map { $0.toDict() },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        let directory = self.directory
        queue.async {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: url, options: Self.writeOptions)
            } catch {
                DiagLog.shared.log("cache", "chat cache write failed: \(error.localizedDescription)")
            }
        }
    }

    public func remove(_ sessionId: String) {
        guard let url = fileURL(sessionId) else { return }
        queue.async { try? FileManager.default.removeItem(at: url) }
    }

    public func prune(keeping: Set<String>) {
        let directory = self.directory
        let keptNames = Set(keeping.compactMap { Self.fileName($0) })
        queue.async {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files where !keptNames.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    public func clear() {
        let directory = self.directory
        queue.async { try? FileManager.default.removeItem(at: directory) }
    }

    /// Blocks until queued writes finish (tests).
    public func waitForWrites() {
        queue.sync {}
    }

    private func fileURL(_ sessionId: String) -> URL? {
        Self.fileName(sessionId).map { directory.appendingPathComponent($0) }
    }

    /// Session ids are UUIDs; anything else is rejected rather than escaped, so a
    /// hostile id can never point outside the cache directory.
    private static func fileName(_ sessionId: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !sessionId.isEmpty, sessionId.count <= 128,
              sessionId.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return sessionId + ".json"
    }

    private static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
        [.atomic]
        #endif
    }
}
