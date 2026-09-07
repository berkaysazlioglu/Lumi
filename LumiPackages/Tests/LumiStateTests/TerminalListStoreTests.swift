import Foundation
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiState

/// Komşu-odak / minimize / lastActiveByRepo kuralları (Electron paritesi) —
/// Faz 3 çıkış kriteri testleri. Event'ler deterministiklik için doğrudan
/// `apply` ile sürülür.
@MainActor
final class TerminalListStoreTests: XCTestCase {
    private var service: FakeTerminalService!
    private var store: TerminalListStore!
    private var toasts: ToastStore!

    override func setUp() async throws {
        service = FakeTerminalService()
        toasts = ToastStore(autoDismissAfter: 60)
        store = TerminalListStore(service: service, toasts: toasts)
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

    // MARK: - Ajan kimliği (karar 45)

    func testProviderChangedUpdatesMetaAndClearsOnNil() {
        let terminal = makeTerminal("t1")
        XCTAssertNil(store.meta(for: terminal.id)?.provider)

        store.apply(.providerChanged(terminal.id, .codex))
        XCTAssertEqual(store.meta(for: terminal.id)?.provider, .codex)

        store.apply(.providerChanged(terminal.id, nil))
        XCTAssertNil(store.meta(for: terminal.id)?.provider)
    }

    // MARK: - Donma rozeti (design/00 Ek A §A.2-10)

    func testStalledEventMarksAndClearsTerminal() {
        // Arrange
        let terminal = makeTerminal("t1")
        XCTAssertFalse(store.isStalled(terminal.id))

        // Act — feed watchdog donma bildirdi
        store.apply(.stalled(terminal.id, true))

        // Assert
        XCTAssertTrue(store.isStalled(terminal.id))
        XCTAssertEqual(store.stalledIDs, [terminal.id])

        // Act — düzeldi
        store.apply(.stalled(terminal.id, false))
        XCTAssertFalse(store.isStalled(terminal.id))
        XCTAssertTrue(store.stalledIDs.isEmpty)
    }

    /// Ephemeral sinyal: donma status'e ya da odağa dokunmaz.
    func testStalledEventDoesNotTouchStatusOrFocus() {
        let first = makeTerminal("t1")
        let second = makeTerminal("t2")
        store.focus(first.id)

        store.apply(.stalled(second.id, true))

        XCTAssertEqual(store.activeTerminalID, first.id)
        XCTAssertEqual(store.meta(for: second.id)?.status, .idle)
    }

    /// Kapanan terminal donmuş listesinde kalmamalı (sızıntı).
    func testExitClearsStalledFlag() {
        let terminal = makeTerminal("t1")
        store.apply(.stalled(terminal.id, true))

        store.apply(.exited(terminal.id, code: 0))

        XCTAssertTrue(store.stalledIDs.isEmpty)
        XCTAssertFalse(store.isStalled(terminal.id))
    }

    // MARK: - Komşu odaklama

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

    // MARK: - View odağı (Faz 3.7: callback yerine event)

    func testViewFocusedEventFocusesTerminal() {
        // Arrange
        let first = makeTerminal("t1")
        let second = makeTerminal("t2")
        store.focus(first.id)

        // Act — terminal NSView'ına tıklama servis event'i olarak gelir
        store.apply(.viewFocused(second.id))

        // Assert
        XCTAssertEqual(store.activeTerminalID, second.id)
        XCTAssertEqual(service.focusCalls.last, second.id)
    }

    func testViewFocusedEventCannotFocusMinimizedTerminal() {
        // Arrange
        let first = makeTerminal("t1")
        let second = makeTerminal("t2")
        store.minimize(first.id)
        store.focus(second.id)

        // Act
        store.apply(.viewFocused(first.id))

        // Assert — minimize kuralı event yolunda da geçerli
        XCTAssertEqual(store.activeTerminalID, second.id)
    }

    // MARK: - Minimize kuralları

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

    // MARK: - Gönderimde otomatik minimize (karar 24)

    func testAutoMinimizeOnWorkingWhenEnabled() {
        store.applyAutoMinimize(true)
        let first = makeTerminal("t1")
        let second = makeTerminal("t2")
        store.focus(second.id)

        store.apply(.statusChanged(second.id, .working))
        XCTAssertTrue(store.isMinimized(second.id))
        XCTAssertEqual(store.activeTerminalID, first.id, "aktif minimize olunca odak komşuya kayar")
    }

    func testAutoMinimizedRestoresOnWaitingWithoutFocus() {
        store.applyAutoMinimize(true)
        let first = makeTerminal("t1")
        let second = makeTerminal("t2")
        store.focus(second.id)
        store.apply(.statusChanged(second.id, .working))

        store.apply(.statusChanged(second.id, .waitingUnseen))
        XCTAssertFalse(store.isMinimized(second.id))
        XCTAssertEqual(store.activeTerminalID, first.id, "otomatik restore odak vermez")
    }

    func testAutoMinimizedRestoresOnIdleAndError() {
        store.applyAutoMinimize(true)
        let first = makeTerminal("t1")
        store.apply(.statusChanged(first.id, .working))
        store.apply(.statusChanged(first.id, .idle))
        XCTAssertFalse(store.isMinimized(first.id))

        store.apply(.statusChanged(first.id, .working))
        store.apply(.statusChanged(first.id, .error))
        XCTAssertFalse(store.isMinimized(first.id))
    }

    func testWorkingDoesNothingWhenDisabled() {
        let only = makeTerminal("t1")

        store.apply(.statusChanged(only.id, .working))
        XCTAssertFalse(store.isMinimized(only.id))
    }

    func testManuallyMinimizedIsNotAutoRestored() {
        store.applyAutoMinimize(true)
        let only = makeTerminal("t1")
        store.minimize(only.id)

        store.apply(.statusChanged(only.id, .working))
        store.apply(.statusChanged(only.id, .waitingUnseen))
        XCTAssertTrue(store.isMinimized(only.id), "elle minimize edilen otomatik restore edilmez")
    }

    func testManualRestoreDuringWorkingDropsTracking() {
        store.applyAutoMinimize(true)
        let only = makeTerminal("t1")
        store.apply(.statusChanged(only.id, .working))
        XCTAssertTrue(store.isMinimized(only.id))

        store.restore(only.id)
        store.apply(.statusChanged(only.id, .waitingUnseen))
        XCTAssertFalse(store.isMinimized(only.id))

        // Sonraki mesaj döngüsü yeniden minimize eder
        store.apply(.statusChanged(only.id, .working))
        XCTAssertTrue(store.isMinimized(only.id))
    }

    func testDisablingToggleMidWorkStillRestores() {
        store.applyAutoMinimize(true)
        let only = makeTerminal("t1")
        store.apply(.statusChanged(only.id, .working))

        store.applyAutoMinimize(false)
        store.apply(.statusChanged(only.id, .waitingUnseen))
        XCTAssertFalse(store.isMinimized(only.id), "toggle kapansa da mahsur kalmaz")
    }

    func testAwaitingDecisionRestoresAutoMinimized() {
        store.applyAutoMinimize(true)
        let only = makeTerminal("t1")
        store.apply(.statusChanged(only.id, .working))
        XCTAssertTrue(store.isMinimized(only.id))

        store.apply(.awaitingDecisionChanged(only.id, true))
        XCTAssertFalse(store.isMinimized(only.id), "izin promptu da girdi bekliyor sayılır")
    }

    // MARK: - lastActiveByRepo (yan etki)

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

    // MARK: - Exit kodu bildirimi (Faz 1.5)

    func testNonZeroExitShowsToast() {
        let terminal = makeTerminal("t1")

        store.apply(.exited(terminal.id, code: 3))

        XCTAssertEqual(toasts.toasts.count, 1)
        XCTAssertEqual(toasts.toasts.first?.kind, .error)
        XCTAssertEqual(toasts.toasts.first?.message, "Terminal exited with code 3")
        XCTAssertEqual(toasts.toasts.first?.title, "t1")
    }

    func testCleanExitShowsNoToast() {
        let terminal = makeTerminal("t1")

        store.apply(.exited(terminal.id, code: 0))

        XCTAssertTrue(toasts.toasts.isEmpty)
    }

    /// Kill sinyallerinden doğan 128+signo kodları (SIGHUP/SIGTERM/SIGKILL)
    /// normal kapanıştır — gürültü yapılmaz.
    func testSignalExitCodesAreSuppressed() {
        for code in [Int32(129), 143, 137] {
            let terminal = makeTerminal("t-\(code)")
            store.apply(.exited(terminal.id, code: code))
        }

        XCTAssertTrue(toasts.toasts.isEmpty)
    }

    /// Kullanıcının kendi kapattığı terminal için toast çıkmaz — kill akışıyla
    /// çakışma yok.
    func testUserInitiatedCloseSuppressesExitToast() {
        let terminal = makeTerminal("t1")

        store.close(terminal.id)
        store.apply(.exited(terminal.id, code: 1))

        XCTAssertTrue(toasts.toasts.isEmpty)
    }

    /// Kullanıcı kill'i takibi tek atımlıdır: aynı id yeniden doğarsa bastırma
    /// devam etmez.
    func testUserCloseSuppressionIsSingleShot() {
        let terminal = makeTerminal("t1")
        store.close(terminal.id)
        store.apply(.exited(terminal.id, code: 1))

        let reborn = makeTerminal("t2")
        store.apply(.exited(reborn.id, code: 1))

        XCTAssertEqual(toasts.toasts.count, 1)
    }

    // MARK: - Yazım hatası bildirimi (Faz 1.15)

    func testWriteFailureShowsToast() {
        let terminal = makeTerminal("t1")

        store.apply(.writeFailed(terminal.id, errno: 32))

        XCTAssertEqual(toasts.toasts.count, 1)
        XCTAssertEqual(toasts.toasts.first?.kind, .error)
        XCTAssertEqual(toasts.toasts.first?.title, "t1")
        XCTAssertEqual(toasts.toasts.first?.message, "Write failed (errno 32)")
    }
}

// MARK: - Sidebar etkinlik zamanı (karar 49)

extension TerminalListStoreTests {
    func testStatusChangeStampsActivityOnlyWhenStatusDiffers() {
        let terminal = makeTerminal("t1")
        XCTAssertNil(store.meta(for: terminal.id)?.statusChangedAt)

        store.apply(.statusChanged(terminal.id, .working))
        let first = store.meta(for: terminal.id)?.statusChangedAt
        XCTAssertNotNil(first)

        store.apply(.statusChanged(terminal.id, .working))
        XCTAssertEqual(store.meta(for: terminal.id)?.statusChangedAt, first, "aynı durumun tekrarı saati ilerletmez")

        store.apply(.statusChanged(terminal.id, .waitingUnseen))
        XCTAssertNotEqual(store.meta(for: terminal.id)?.statusChangedAt, first)
    }
}
