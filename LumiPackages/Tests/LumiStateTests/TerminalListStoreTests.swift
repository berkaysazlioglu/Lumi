import Foundation
import XCTest
import LumiKit
@testable import LumiState

/// Komşu-odak / minimize / lastActiveByRepo kuralları (spec/21 §5-7 birebir) —
/// Faz 3 çıkış kriteri testleri. Event'ler deterministiklik için doğrudan
/// `apply` ile sürülür.
@MainActor
final class TerminalListStoreTests: XCTestCase {
    private var service: FakeTerminalService!
    private var store: TerminalListStore!

    override func setUp() async throws {
        service = FakeTerminalService()
        store = TerminalListStore(service: service, toasts: ToastStore(autoDismissAfter: 60))
    }

    private func makeTerminal(_ name: String, repo: String = "/repo/a") -> TerminalMeta {
        let meta = TerminalMeta(
            id: TerminalID(),
            name: name,
            repoPath: repo,
            createdAt: Date()
        )
        store.apply(.spawned(meta))
        return meta
    }

    // MARK: - Komşu odaklama (spec/21 §5)

    func testClosingActiveFocusesPreviousNeighbor() {
        let first = makeTerminal("t1")
        let second = makeTerminal("t2")
        _ = makeTerminal("t3")
        store.focus(second.id)

        store.apply(.exited(second.id, code: 0))
        XCTAssertEqual(store.activeTerminalID, first.id, "önceki komşu odaklanmalı")
    }

    func testClosingFirstFocusesNext() {
        let first = makeTerminal("t1")
        let second = makeTerminal("t2")
        store.focus(first.id)

        store.apply(.exited(first.id, code: 0))
        XCTAssertEqual(store.activeTerminalID, second.id)
    }

    func testFocusNeverCrossesRepo() {
        let repoA = makeTerminal("a1", repo: "/repo/a")
        _ = makeTerminal("b1", repo: "/repo/b")
        store.focus(repoA.id)

        store.apply(.exited(repoA.id, code: 0))
        // Aynı repoda görünür terminal kalmadı → aktif nil (başka repoya atlamaz)
        XCTAssertNil(store.activeTerminalID)
    }

    func testClosingInactiveKeepsActive() {
        let first = makeTerminal("t1")
        let second = makeTerminal("t2")
        store.focus(second.id)

        store.apply(.exited(first.id, code: 0))
        XCTAssertEqual(store.activeTerminalID, second.id)
    }

    func testMinimizedExcludedFromNeighborCandidates() {
        let first = makeTerminal("t1")
        let second = makeTerminal("t2")
        let third = makeTerminal("t3")
        store.minimize(first.id)
        store.focus(second.id)

        store.apply(.exited(second.id, code: 0))
        XCTAssertEqual(store.activeTerminalID, third.id, "minimize edilmiş komşu aday olamaz")
    }

    // MARK: - Minimize kuralları (spec/21 §6)

    func testMinimizeActiveShiftsFocusToVisibleSibling() {
        let first = makeTerminal("t1")
        let second = makeTerminal("t2")
        store.focus(second.id)

        store.minimize(second.id)
        XCTAssertTrue(store.isMinimized(second.id))
        XCTAssertEqual(store.activeTerminalID, first.id)
    }

    func testMinimizedTerminalCannotReceiveFocus() {
        let first = makeTerminal("t1")
        let second = makeTerminal("t2")
        store.minimize(first.id)
        store.focus(second.id)

        store.focus(first.id)
        XCTAssertEqual(store.activeTerminalID, second.id, "minimize edilmiş odak alamaz")
    }

    func testRestoreDoesNotFocus() {
        let first = makeTerminal("t1")
        let second = makeTerminal("t2")
        store.minimize(first.id)
        store.focus(second.id)

        store.restore(first.id)
        XCTAssertFalse(store.isMinimized(first.id))
        XCTAssertEqual(store.activeTerminalID, second.id)
    }

    func testRestoreAndFocusIsTheNotificationException() {
        let first = makeTerminal("t1")
        let second = makeTerminal("t2")
        store.minimize(first.id)
        store.focus(second.id)

        store.restoreAndFocus(first.id)
        XCTAssertEqual(store.activeTerminalID, first.id)
    }

    // MARK: - lastActiveByRepo (spec/21 §9 yan etkisi)

    func testActivateRepoRestoresLastActive() {
        _ = makeTerminal("a1", repo: "/repo/a")
        let secondA = makeTerminal("a2", repo: "/repo/a")
        store.focus(secondA.id)
        let repoB = makeTerminal("b1", repo: "/repo/b")
        store.focus(repoB.id)

        store.activateRepo("/repo/a")
        XCTAssertEqual(store.activeTerminalID, secondA.id)
    }

    func testActivateRepoFallsBackToFirstVisible() {
        let firstA = makeTerminal("a1", repo: "/repo/a")
        let secondA = makeTerminal("a2", repo: "/repo/a")
        store.focus(secondA.id)
        store.minimize(secondA.id) // lastActive artık görünür değil

        store.activateRepo("/repo/a")
        XCTAssertEqual(store.activeTerminalID, firstA.id)
    }

    func testActivateRepoWithNoVisibleTerminalsClearsFocus() {
        let only = makeTerminal("a1", repo: "/repo/a")
        store.minimize(only.id)

        store.activateRepo("/repo/a")
        XCTAssertNil(store.activeTerminalID)
    }

    // MARK: - Klavye navigasyonu

    func testFocusIndexTargetsVisibleSet() {
        let first = makeTerminal("t1")
        let second = makeTerminal("t2")
        let third = makeTerminal("t3")
        store.minimize(second.id)

        store.focusIndex(1, in: "/repo/a") // görünürler: [t1, t3]
        XCTAssertEqual(store.activeTerminalID, third.id)
        store.focusIndex(0, in: "/repo/a")
        XCTAssertEqual(store.activeTerminalID, first.id)
    }

    func testFocusNextWrapsAround() {
        let first = makeTerminal("t1")
        let second = makeTerminal("t2")
        store.focus(second.id)

        store.focusNext(in: "/repo/a")
        XCTAssertEqual(store.activeTerminalID, first.id)
        store.focusPrevious(in: "/repo/a")
        XCTAssertEqual(store.activeTerminalID, second.id)
    }

    // MARK: - Spawn / intent köprüleri

    func testSpawnEventFocusesNewTerminal() {
        let meta = makeTerminal("t1")
        XCTAssertEqual(store.activeTerminalID, meta.id)
    }

    func testCloseAllSendsKillPerTerminal() {
        let first = makeTerminal("t1")
        let second = makeTerminal("t2")
        _ = makeTerminal("other", repo: "/repo/b")

        store.closeAll(in: "/repo/a")
        XCTAssertEqual(Set(service.killedIDs), Set([first.id, second.id]))
    }
}
