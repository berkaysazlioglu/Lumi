import XCTest
import LumiWire
@testable import LumiMobileKit

final class InMemoryChatCache: ChatCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: ChatCacheEntry] = [:]
    var stored: [String: ChatCacheEntry] { lock.withLock { entries } }

    init(_ seed: [String: ChatCacheEntry] = [:]) { entries = seed }
    func load(_ sessionId: String) -> ChatCacheEntry? { lock.withLock { entries[sessionId] } }
    func save(_ sessionId: String, entry: ChatCacheEntry) { lock.withLock { entries[sessionId] = entry } }
    func remove(_ sessionId: String) { lock.withLock { _ = entries.removeValue(forKey: sessionId) } }
    func prune(keeping: Set<String>) { lock.withLock { entries = entries.filter { keeping.contains($0.key) } } }
    func clear() { lock.withLock { entries = [:] } }
}

private func msg(_ id: String) -> ChatMessage {
    ChatMessage(id: id, role: .assistant, blocks: [.text("t-\(id)", presentation: nil)], timestampMs: 1, turnId: nil)
}

/// Decision 130 (phase 3): on-disk chat cache.
final class FileChatCacheTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-cache-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRoundTripsMessages() {
        let cache = FileChatCache(directory: directory)
        let id = UUID().uuidString
        cache.save(id, entry: ChatCacheEntry(messages: [msg("a"), msg("b")], hasEarlier: false))
        XCTAssertEqual(cache.load(id), ChatCacheEntry(messages: [msg("a"), msg("b")], hasEarlier: false))
    }

    func testKeepsNewestMessagesAndFlagsEarlier() {
        let cache = FileChatCache(directory: directory)
        let id = UUID().uuidString
        let all = (0..<(FileChatCache.maxMessages + 5)).map { msg("m\($0)") }
        cache.save(id, entry: ChatCacheEntry(messages: all, hasEarlier: false))
        let loaded = cache.load(id)
        XCTAssertEqual(loaded?.messages.count, FileChatCache.maxMessages)
        XCTAssertEqual(loaded?.messages.last?.id, all.last?.id)
        XCTAssertEqual(loaded?.hasEarlier, true)
    }

    func testOlderFormatFileIsDropped() throws {
        let cache = FileChatCache(directory: directory)
        let id = UUID().uuidString
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(id + ".json")
        try Data(#"{"v":1,"hasEarlier":false,"messages":[]}"#.utf8).write(to: file)
        XCTAssertNil(cache.load(id), "a v1 file may hold an unanchored list")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testPruneDropsSessionsNotKept() {
        let cache = FileChatCache(directory: directory)
        let keep = UUID().uuidString, drop = UUID().uuidString
        cache.save(keep, entry: ChatCacheEntry(messages: [msg("a")], hasEarlier: false))
        cache.save(drop, entry: ChatCacheEntry(messages: [msg("b")], hasEarlier: false))
        cache.prune(keeping: [keep])
        cache.waitForWrites()
        XCTAssertNotNil(cache.load(keep))
        XCTAssertNil(cache.load(drop))
    }

    func testRejectsIdsThatCouldEscapeTheDirectory() {
        let cache = FileChatCache(directory: directory)
        cache.save("../evil", entry: ChatCacheEntry(messages: [msg("a")], hasEarlier: false))
        cache.waitForWrites()
        XCTAssertNil(cache.load("../evil"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.deletingLastPathComponent()
            .appendingPathComponent("evil.json").path))
    }
}

@MainActor
final class AppModelChatCacheTests: XCTestCase {
    private func makeModel(_ cache: InMemoryChatCache) -> AppModel {
        let store = InMemorySecureStore()
        store.write(PairingInfo(relayUrl: "wss://r.example", token: "0123456789abcdef"))
        let model = AppModel(client: FakeRelayClient(), store: store, chatCache: cache)
        model.chatCacheDelay = .milliseconds(10)
        return model
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    func testColdStartShowsCachedChatUntilSnapshotReplacesIt() {
        let cache = InMemoryChatCache(["s1": ChatCacheEntry(messages: [msg("a")], hasEarlier: true)])
        let model = makeModel(cache)
        model.subscribeChat("s1")
        XCTAssertEqual(model.chatMessages("s1").map(\.id), ["a"])
        XCTAssertTrue(model.chatHasEarlier.contains("s1"))
        XCTAssertTrue(model.chatSyncing.contains("s1"))
        model.handle(.chat(sessionId: "s1", messages: [msg("a"), msg("b")]))
        XCTAssertEqual(model.chatMessages("s1").map(\.id), ["a", "b"])
        XCTAssertFalse(model.chatHasEarlier.contains("s1"))
    }

    func testIncomingChatIsWrittenToCache() async {
        let cache = InMemoryChatCache()
        let model = makeModel(cache)
        model.handle(.chat(sessionId: "s1", messages: [msg("a")]))
        model.handle(.chatAppend(sessionId: "s1", messages: [msg("b")]))
        await waitUntil { cache.stored["s1"]?.messages.count == 2 }
        XCTAssertEqual(cache.stored["s1"]?.messages.map(\.id), ["a", "b"])
    }

    func testClearSnapshotEmptiesCache() async {
        let cache = InMemoryChatCache(["s1": ChatCacheEntry(messages: [msg("a")], hasEarlier: false)])
        let model = makeModel(cache)
        model.subscribeChat("s1")
        model.handle(.chat(sessionId: "s1", messages: []))   // decision 94: /clear
        await waitUntil { cache.stored["s1"]?.messages.isEmpty == true }
        XCTAssertEqual(cache.stored["s1"]?.messages, [])
    }

    func testMacSessionsPruneCache() {
        let cache = InMemoryChatCache([
            "live": ChatCacheEntry(messages: [msg("a")], hasEarlier: false),
            "gone": ChatCacheEntry(messages: [msg("b")], hasEarlier: false),
        ])
        let model = makeModel(cache)
        model.handle(.sessions([SessionMeta(id: "live", repoName: "r", status: "idle", title: nil,
                                            model: nil, cols: 80, rows: 24, kind: "chat")]))
        XCTAssertEqual(Set(cache.stored.keys), ["live"])
    }

    func testUnpairClearsCache() async {
        let cache = InMemoryChatCache(["s1": ChatCacheEntry(messages: [msg("a")], hasEarlier: false)])
        let model = makeModel(cache)
        await model.unpair()
        XCTAssertTrue(cache.stored.isEmpty)
    }
}
