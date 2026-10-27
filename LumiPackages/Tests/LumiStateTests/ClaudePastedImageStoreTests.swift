import Foundation
import LumiKit
import XCTest
@testable import LumiState

/// Karar 139: kart header'ındaki görsel listesi.
@MainActor
final class ClaudePastedImageStoreTests: XCTestCase {
    func testListsImagesOfTrackedClaudeSession() async {
        let listed = LockedBox<[String]>([])
        let store = ClaudePastedImageStore(userID: 7) { directory in
            listed.mutate { $0.append(directory) }
            return ["2.png", "1.png", "x.txt"]
        }
        var meta = TerminalMeta(id: TerminalID(), name: "t", repoPath: "/repo", createdAt: Date())
        XCTAssertFalse(store.hasImageDirectory(meta))
        let none = await store.images(for: meta)
        XCTAssertEqual(none, [])
        XCTAssertEqual(listed.value, [], "oturumsuz terminalde disk okunmaz")

        meta.claudeSessionID = "s"
        XCTAssertTrue(store.hasImageDirectory(meta))
        let images = await store.images(for: meta)
        XCTAssertEqual(images.map(\.number), [1, 2])
        XCTAssertEqual(listed.value, ["/private/tmp/claude-7/-repo/s/images"])
    }
}

private final class LockedBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.withLock { stored } }
    func mutate(_ change: (inout Value) -> Void) { lock.withLock { change(&stored) } }
}
