import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Faz 4.9 — odak otoritesinin birleştirilmesi + Faz 4A "Beklenen davranış
/// tablosu"nun store/servis düzeyindeki karşılığı.
///
/// | Olay | View | PTY | Status makinesi | Coalescer |
/// |---|---|---|---|---|
/// | Tasks'a geçiş | detach | çalışır | `onBlur()` | 100ms |
/// | Tasks açıkken resize | frame donuk | resize yok | değişmez | 100ms |
/// | Grid'e dönüş | attach + tek fit | tek resize | `onFocus()` yalnız aktif | 16ms |
/// | Tasks açıkken exit | — | reap | `onExit(code)` | flush |
///
/// Status makinesi/coalescer tarafı `TerminalSurfaceStateTests`'te doğrulanır;
/// burada store'un o kanala DOĞRU sinyali gönderdiği kilitlenir.
@MainActor
final class TerminalSurfaceIntentTests: XCTestCase {
    private var service: FakeTerminalService!
    private var store: TerminalListStore!
    private var toasts: ToastStore!

    override func setUp() async throws {
        service = FakeTerminalService()
        toasts = ToastStore(autoDismissAfter: 60)
        store = TerminalListStore(service: service, toasts: toasts)
    }

    @discardableResult
    private func makeTerminal(_ name: String, repo: String = "/repo/a") -> TerminalMeta {
        let meta = TerminalMeta(id: TerminalID(), name: name, repoPath: repo, createdAt: Date())
        store.apply(.spawned(meta))
        return meta
    }

    // MARK: - Tek intent

    /// Tasks'a geçiş: yüzey arkaya düşer (→ `onBlur` + 100ms), servise
    /// `setFocused(nil)` gider ama `activeTerminalID` KORUNUR — dönüşte
    /// aynı terminal geri odaklanabilsin.
    func testHidingSurfaceBackgroundsRepoAndClearsServiceFocusButKeepsActive() {
        let terminal = makeTerminal("t1")
        XCTAssertEqual(store.activeTerminalID, terminal.id)

        store.setTerminalSurfaceVisible(false, in: "/repo/a")

        XCTAssertEqual(
            service.surfaceStateCalls,
            [.init(state: .background, id: nil, repoPath: "/repo/a")]
        )
        XCTAssertEqual(service.focusCalls.last, .some(nil), "servise blur gitmedi")
        XCTAssertEqual(store.activeTerminalID, terminal.id, "aktif terminal kaybedildi")
    }

    /// Grid'e dönüş: yüzey öne gelir (→ 16ms) ve yalnız AKTİF terminal
    /// yeniden odaklanır (`onFocus` yalnız aktif).
    func testShowingSurfaceForegroundsRepoAndRefocusesActiveTerminal() {
        let first = makeTerminal("t1")
        let second = makeTerminal("t2")
        store.focus(second.id)
        store.setTerminalSurfaceVisible(false, in: "/repo/a")

        store.setTerminalSurfaceVisible(true, in: "/repo/a")

        XCTAssertEqual(
            service.surfaceStateCalls.last,
            .init(state: .foreground, id: nil, repoPath: "/repo/a")
        )
        XCTAssertEqual(service.focusCalls.last, second.id)
        XCTAssertNotEqual(service.focusCalls.last, first.id)
    }

    func testShowingSurfaceWithoutActiveTerminalDoesNotForceFocus() {
        makeTerminal("t1", repo: "/repo/b")
        store.focus(nil)
        service.resetFocusCalls()

        store.setTerminalSurfaceVisible(true, in: "/repo/a")

        XCTAssertEqual(
            service.surfaceStateCalls.last,
            .init(state: .foreground, id: nil, repoPath: "/repo/a")
        )
        XCTAssertTrue(service.focusCalls.isEmpty, "boş repoda odak zorlandı")
    }

    /// Minimize edilmiş aktif terminal dönüşte odak ALMAZ (değişmez kural).
    func testShowingSurfaceSkipsMinimizedActiveTerminal() {
        let terminal = makeTerminal("t1")
        store.minimize(terminal.id) // aktiflik komşu yokken korunmaz → nil
        store.setTerminalSurfaceVisible(false, in: "/repo/a")
        service.resetFocusCalls()

        store.setTerminalSurfaceVisible(true, in: "/repo/a")

        XCTAssertTrue(service.focusCalls.isEmpty)
    }

    // MARK: - Beklenen davranış tablosu

    /// "Tasks açıkken resize": store yüzey gizliyken PTY'ye resize trafiği üretmez.
    func testNoResizeTrafficWhileSurfaceHidden() {
        makeTerminal("t1")

        store.setTerminalSurfaceVisible(false, in: "/repo/a")

        XCTAssertTrue(service.resizeCalls.isEmpty)
    }

    /// "Tasks açıkken exit": yüzey gizliyken gelen exit normal işlenir —
    /// terminal listeden düşer, komşu odağı hesaplanır, yüzey durumu bozulmaz.
    func testExitWhileSurfaceHiddenStillRemovesTerminalAndPicksNeighbor() {
        let first = makeTerminal("t1")
        let second = makeTerminal("t2")
        store.focus(second.id)
        store.setTerminalSurfaceVisible(false, in: "/repo/a")
        let surfaceCallsBefore = service.surfaceStateCalls.count

        store.apply(.exited(second.id, code: 0))

        XCTAssertEqual(store.terminals.map(\.id), [first.id])
        XCTAssertEqual(store.activeTerminalID, first.id)
        XCTAssertEqual(
            service.surfaceStateCalls.count,
            surfaceCallsBefore,
            "exit yüzey durumunu değiştirmemeli"
        )
    }

    // MARK: - Tab geçişi (davranış değişikliği)

    /// DAVRANIŞ DEĞİŞİKLİĞİ (4.9): tab geçişinde eski reponun terminalleri artık
    /// `.background` alır → `statusMachine.onBlur()`. Önceden yalnız coalescer
    /// aralığı değişiyordu, odak bayrağı eski repoda takılı kalıyordu.
    func testActivateRepoBackgroundsPreviousRepoAndForegroundsNext() {
        let repoATerminal = makeTerminal("a1", repo: "/repo/a")
        store.activateRepo("/repo/a")
        let repoBTerminal = makeTerminal("b1", repo: "/repo/b")
        store.activateRepo("/repo/b")

        XCTAssertEqual(
            service.surfaceStateCalls.suffix(3),
            [
                .init(state: .foreground, id: nil, repoPath: "/repo/a"),
                .init(state: .background, id: nil, repoPath: "/repo/a"),
                .init(state: .foreground, id: nil, repoPath: "/repo/b")
            ]
        )
        XCTAssertEqual(store.activeTerminalID, repoBTerminal.id)
        XCTAssertNotEqual(store.activeTerminalID, repoATerminal.id)
    }

    func testActivateSameRepoTwiceDoesNotBackgroundIt() {
        makeTerminal("a1", repo: "/repo/a")
        store.activateRepo("/repo/a")
        store.activateRepo("/repo/a")

        XCTAssertFalse(
            service.surfaceStateCalls.contains { $0.state == .background },
            "aynı repoya dönüş kendini arkaya attı"
        )
    }

    func testActivateRepoStillRestoresLastActiveTerminal() {
        makeTerminal("a1", repo: "/repo/a")
        let secondA = makeTerminal("a2", repo: "/repo/a")
        store.focus(secondA.id)
        let repoB = makeTerminal("b1", repo: "/repo/b")
        store.focus(repoB.id)

        store.activateRepo("/repo/a")

        XCTAssertEqual(store.activeTerminalID, secondA.id)
        XCTAssertEqual(service.focusCalls.last, secondA.id)
    }

    // MARK: - Minimize / restore (karar 24)

    func testMinimizeUsesMinimizedSurfaceStateAndRestoreForegrounds() {
        let terminal = makeTerminal("t1")

        store.minimize(terminal.id)
        XCTAssertEqual(
            service.surfaceStateCalls.last,
            .init(state: .minimized, id: terminal.id, repoPath: nil)
        )

        store.restore(terminal.id)
        XCTAssertEqual(
            service.surfaceStateCalls.last,
            .init(state: .foreground, id: terminal.id, repoPath: nil)
        )
    }

    /// Karar 24'ün otomatik restore'u her repoda çalışır; arka plandaki tab'ın
    /// kartı ekrana dönmediği için öne ALINMAZ.
    func testRestoreInBackgroundRepoDoesNotForegroundIt() {
        let background = makeTerminal("b1", repo: "/repo/b")
        makeTerminal("a1", repo: "/repo/a")
        store.minimize(background.id)
        store.activateRepo("/repo/a")

        store.restore(background.id)

        XCTAssertNotEqual(
            service.surfaceStateCalls.last,
            .init(state: .foreground, id: background.id, repoPath: nil)
        )
    }

    func testAutoMinimizeOnSendPushesMinimizedSurfaceState() {
        store.autoMinimizeOnSend = true
        let terminal = makeTerminal("t1")

        store.apply(.statusChanged(terminal.id, .working))

        XCTAssertTrue(store.isMinimized(terminal.id))
        XCTAssertEqual(
            service.surfaceStateCalls.last,
            .init(state: .minimized, id: terminal.id, repoPath: nil)
        )
    }
}
