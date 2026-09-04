import Foundation
import XCTest
@testable import LumiState

/// `KeyedToggleSet` — üç kopyanın (selectedFiles / expandedBranches /
/// expandedNodes) tek tipi (refactor 5.5).
final class KeyedToggleSetTests: XCTestCase {
    func testSubscriptKeepsDictionaryParityForMissingKeys() {
        let set = KeyedToggleSet<String, String>()
        XCTAssertNil(set["/r"], "yazılmamış anahtar nil döner (çağıranların ?? [] kalıbı korunur)")
        XCTAssertFalse(set.contains("a", in: "/r"))
    }

    func testToggleIsSymmetricAndCreatesKey() {
        var set = KeyedToggleSet<String, String>()
        set.toggle("a", in: "/r")
        XCTAssertEqual(set["/r"], ["a"])
        set.toggle("a", in: "/r")
        XCTAssertEqual(set["/r"], [], "anahtar kalır, küme boşalır")
    }

    func testKeysAreIsolated() {
        var set = KeyedToggleSet<String, String>()
        set.insert("a", in: "/r1")
        XCTAssertTrue(set.contains("a", in: "/r1"))
        XCTAssertFalse(set.contains("a", in: "/r2"))
    }

    func testFormUnionAccumulates() {
        var set = KeyedToggleSet<String, String>()
        set.formUnion(["a", "b"], in: "/r")
        set.formUnion(["b", "c"], in: "/r")
        XCTAssertEqual(set["/r"], ["a", "b", "c"])
    }

    func testReplaceOverwritesWholeSet() {
        var set = KeyedToggleSet<String, String>()
        set.formUnion(["a", "b"], in: "/r")
        set.replace(["c"], in: "/r")
        XCTAssertEqual(set["/r"], ["c"])
    }

    func testEvictRemovesKeyEntirely() {
        var set = KeyedToggleSet<String, String>()
        set.insert("a", in: "/r")
        set.evict("/r")
        XCTAssertNil(set["/r"], "replace ile karıştırılmaz: anahtar tamamen gider")
        XCTAssertTrue(set.isEmpty)
    }
}
