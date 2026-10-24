import Foundation
import LumiKit
import XCTest
@testable import LumiState

/// Karar 135: Custom View'ların saf kuralları — üyelik, boş view'ın silinmesi,
/// açılışta resume kimlikleriyle geri kurulum.
final class CustomTerminalViewsTests: XCTestCase {
    private func meta(_ name: String, repo: String = "/r/alpha", claude: String? = nil) -> TerminalMeta {
        TerminalMeta(
            id: TerminalID(), name: name, repoPath: repo, createdAt: Date(),
            claudeSessionID: claude, provider: claude == nil ? nil : .claude
        )
    }

    private func names(_ metas: [TerminalMeta]) -> [String] {
        metas.map(\.name)
    }

    // MARK: - Üyelik

    func testViewShowsOnlyItsMembersInInsertionOrder() {
        let a = meta("a"), b = meta("b", repo: "/r/beta"), c = meta("c")
        var views = CustomTerminalViews()
        let view = views.create(with: c.id, name: "V")
        views.add(a.id, to: view)

        XCTAssertEqual(names(views.members(of: view, among: [a, b, c])), ["c", "a"])
    }

    func testAddingAnExistingMemberIsANoOp() {
        let a = meta("a")
        var views = CustomTerminalViews()
        let view = views.create(with: a.id, name: "V")
        XCTAssertFalse(views.add(a.id, to: view))
        XCTAssertFalse(views.add(a.id, to: CustomViewID(rawValue: "missing")))
    }

    func testTerminalCanBelongToSeveralViews() {
        let a = meta("a"), b = meta("b")
        var views = CustomTerminalViews()
        let first = views.create(with: a.id, name: "First")
        let second = views.create(with: b.id, name: "Second")
        views.add(a.id, to: second)

        XCTAssertEqual(views.views(containing: a, among: [a, b]).map(\.id), [first, second])
    }

    // MARK: - Boş view yoktur

    func testRemovingTheLastMemberDeletesTheView() {
        let a = meta("a"), b = meta("b")
        var views = CustomTerminalViews()
        let view = views.create(with: a.id, name: "V")
        views.add(b.id, to: view)

        XCTAssertEqual(views.remove(a.id, from: view).removed, [])
        XCTAssertEqual(views.remove(b.id, from: view).removed, [view])
        XCTAssertNil(views.view(view))
    }

    func testExitedMembersDropAndEmptyViewIsDeleted() {
        let a = meta("a"), b = meta("b")
        var views = CustomTerminalViews()
        let keep = views.create(with: a.id, name: "Keep")
        views.add(b.id, to: keep)
        let gone = views.create(with: b.id, name: "Gone")

        let removed = views.pin([a])

        XCTAssertEqual(removed, [gone])
        XCTAssertEqual(names(views.members(of: keep, among: [a])), ["a"])
    }

    func testSwapStaysInsideTheView() {
        let a = meta("a"), b = meta("b"), outsider = meta("x")
        var views = CustomTerminalViews()
        let view = views.create(with: a.id, name: "V")
        views.add(b.id, to: view)

        XCTAssertTrue(views.swap(a.id, b.id, in: view, among: [a, b, outsider]))
        XCTAssertFalse(views.swap(a.id, outsider.id, in: view, among: [a, b, outsider]))
        XCTAssertEqual(names(views.members(of: view, among: [a, b, outsider])), ["b", "a"])
    }

    func testRenameValidatesTheName() {
        let a = meta("a")
        var views = CustomTerminalViews()
        let view = views.create(with: a.id, name: "Old")

        XCTAssertFalse(views.rename(view, to: "   "))
        XCTAssertTrue(views.rename(view, to: "  Review  "))
        XCTAssertEqual(views.view(view)?.name, "Review")
        XCTAssertFalse(views.rename(view, to: "Review"), "aynı ad değişiklik değildir")
    }

    // MARK: - Kalıcılık

    func testPersistedKeepsOnlyResumableMembersAndSkipsViewsWithoutThem() {
        let claude = meta("c", claude: "s-1"), shell = meta("sh")
        var views = CustomTerminalViews()
        let mixed = views.create(with: shell.id, name: "Mixed")
        views.add(claude.id, to: mixed)
        views.create(with: shell.id, name: "Shell only")

        XCTAssertEqual(views.persisted([claude, shell]), [
            CustomViewState(id: mixed.rawValue, name: "Mixed", order: ["s-1"]),
        ])
    }

    func testRestoredViewWaitsForResumedSessionsAndDropsThoseThatNeverSpawn() {
        var views = CustomTerminalViews(restoring: [
            CustomViewState(id: "v-1", name: "Both", order: ["s-2", "s-1"]),
            CustomViewState(id: "v-2", name: "Dead", order: ["s-9"]),
            CustomViewState(id: "v-3", name: "Empty", order: []),
        ])
        XCTAssertEqual(views.views.map(\.name), ["Both", "Dead"], "sırası boş kayıt alınmaz")

        // Doğmamış oturumlar view'ı ayakta tutar.
        XCTAssertEqual(views.pin([]), [])

        let first = meta("first", claude: "s-1")
        let second = meta("second", repo: "/r/beta", claude: "s-2")
        let removed = views.finishRestore(aliveKeys: ["s-1", "s-2"], metas: [first])

        XCTAssertEqual(removed, [CustomViewID(rawValue: "v-2")])
        let both = CustomViewID(rawValue: "v-1")
        XCTAssertEqual(names(views.members(of: both, among: [first])), ["first"])
        // Doğmuş ama store'a henüz yansımamış oturum yerine oturur.
        XCTAssertEqual(names(views.members(of: both, among: [first, second])), ["second", "first"])
    }

    // MARK: - Ad üretimi

    func testRandomNameAvoidsExistingNames() {
        var generator = SeededGenerator(seed: 7)
        let taken = Set(CustomViewName.adjectives.flatMap { adjective in
            CustomViewName.nouns.dropLast().map { "\(adjective) \($0)" }
        })

        let name = CustomViewName.random(excluding: taken, using: &generator)

        XCTAssertFalse(taken.contains(name))
        XCTAssertTrue(name.hasSuffix(CustomViewName.nouns.last!))
    }

    func testRandomNameFallsBackToNumberedNameWhenExhausted() {
        var generator = SeededGenerator(seed: 1)
        let all = Set(CustomViewName.adjectives.flatMap { adjective in
            CustomViewName.nouns.map { "\(adjective) \($0)" }
        })
        XCTAssertEqual(CustomViewName.random(excluding: all.union(["View 1"]), using: &generator), "View 2")
    }

    func testRouteIDRoundTrip() {
        let id = CustomViewID(rawValue: "abc")
        let route = WorkspaceRoute.content(.customView(id))

        XCTAssertEqual(route.terminalScope, .custom(id))
        XCTAssertEqual(ContentRouteID.customView(id).family, .customViewFamily)
        XCTAssertNil(ContentRouteID("customView:").customViewID)
        XCTAssertNil(ContentRouteID.allTerminals.customViewID)
    }
}

/// Testler için belirlenimci üreteç (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
