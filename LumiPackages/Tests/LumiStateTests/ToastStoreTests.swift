import XCTest
import LumiKit
@testable import LumiState

@MainActor
final class ToastStoreTests: XCTestCase {
    func testShowAddsToast() {
        let store = ToastStore(autoDismissAfter: 60)
        store.show(.info, title: "Hello")
        XCTAssertEqual(store.toasts.count, 1)
        XCTAssertEqual(store.toasts.first?.title, "Hello")
    }

    func testMaxFiveDropsOldest() {
        let store = ToastStore(autoDismissAfter: 60)
        for index in 0..<6 {
            store.show(.info, title: "toast-\(index)")
        }
        XCTAssertEqual(store.toasts.count, ToastStore.maxToasts)
        XCTAssertEqual(store.toasts.first?.title, "toast-1")
    }

    func testDuplicateIsDeduped() {
        let store = ToastStore(autoDismissAfter: 60)
        store.show(.error, title: "Error", message: "same")
        store.show(.error, title: "Error", message: "same")
        XCTAssertEqual(store.toasts.count, 1)
    }

    func testAutoDismiss() async throws {
        let store = ToastStore(autoDismissAfter: 0.05)
        store.show(.info, title: "fleeting")
        XCTAssertEqual(store.toasts.count, 1)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(store.toasts.isEmpty, "toast otomatik kapanmalıydı")
    }

    func testManualDismiss() {
        let store = ToastStore(autoDismissAfter: 60)
        store.show(.info, title: "bye")
        let id = store.toasts[0].id
        store.dismiss(id)
        XCTAssertTrue(store.toasts.isEmpty)
    }

    func testReportingMapsLumiErrorToToast() {
        // Karar 5: spawn hatası dahil her hata görünür
        let store = ToastStore(autoDismissAfter: 60)
        store.reporting {
            throw LumiError.spawnFailed(reason: "pty")
        }
        XCTAssertEqual(store.toasts.count, 1)
        XCTAssertEqual(store.toasts.first?.kind, .error)
        XCTAssertTrue(store.toasts.first?.message.contains("pty") == true)
    }

    func testReportingPassesThroughSuccess() {
        let store = ToastStore(autoDismissAfter: 60)
        store.reporting {}
        XCTAssertTrue(store.toasts.isEmpty)
    }

    // MARK: - Bell dedupe: TERMİNAL BAŞINA en çok bir aktif bell (2.5)

    func testSecondBellForSameTerminalIsSuppressed() {
        let store = ToastStore(autoDismissAfter: 60)
        let id = TerminalID()

        store.show(.bell, title: "alpha", message: "first", terminalID: id)
        store.show(.bell, title: "alpha", message: "second", terminalID: id)

        XCTAssertEqual(store.toasts.count, 1, "başlık/mesaj farklı olsa da terminal başına tek bell")
        XCTAssertEqual(store.toasts.first?.message, "first", "ilk gelen kalır")
    }

    func testBellsForDifferentTerminalsCoexist() {
        let store = ToastStore(autoDismissAfter: 60)
        store.show(.bell, title: "alpha", message: "", terminalID: TerminalID())
        store.show(.bell, title: "alpha", message: "", terminalID: TerminalID())

        XCTAssertEqual(store.toasts.count, 2, "dedupe anahtarı terminal id'sidir, içerik değil")
    }

    func testBellIsAllowedAgainAfterItsToastIsDismissed() {
        let store = ToastStore(autoDismissAfter: 60)
        let id = TerminalID()
        store.show(.bell, title: "alpha", message: "", terminalID: id)
        store.dismiss(store.toasts[0].id)

        store.show(.bell, title: "alpha", message: "", terminalID: id)
        XCTAssertEqual(store.toasts.count, 1, "kural AKTİF toast'lar üzerinden işler")
    }

    /// terminalID'siz bell, terminal-bazlı kurala girmez → içerik dedupe'una düşer.
    func testBellWithoutTerminalFallsBackToContentDedupe() {
        let store = ToastStore(autoDismissAfter: 60)
        store.show(.bell, title: "alpha", message: "x")
        store.show(.bell, title: "alpha", message: "x")
        XCTAssertEqual(store.toasts.count, 1)

        store.show(.bell, title: "alpha", message: "y")
        XCTAssertEqual(store.toasts.count, 2, "farklı içerik → ayrı toast")
    }

    func testBellRuleDoesNotSuppressOtherKinds() {
        let store = ToastStore(autoDismissAfter: 60)
        let id = TerminalID()
        store.show(.bell, title: "alpha", message: "", terminalID: id)
        store.show(.error, title: "alpha", message: "", terminalID: id)

        XCTAssertEqual(store.toasts.count, 2, "bell kuralı yalnız bell↔bell çiftinde geçerli")
    }

    func testNonBellDedupeComparesKindTitleAndMessage() {
        let store = ToastStore(autoDismissAfter: 60)
        store.show(.info, title: "t", message: "m")
        store.show(.info, title: "t", message: "m")
        XCTAssertEqual(store.toasts.count, 1)

        store.show(.info, title: "t", message: "other")
        store.show(.success, title: "t", message: "m")
        XCTAssertEqual(store.toasts.count, 3)
    }

    func testDroppedOldestToastAlsoReleasesItsBellSlot() {
        let store = ToastStore(autoDismissAfter: 60)
        let id = TerminalID()
        store.show(.bell, title: "bell", message: "", terminalID: id)
        for index in 0 ..< ToastStore.maxToasts {
            store.show(.info, title: "i\(index)")
        }
        XCTAssertEqual(store.toasts.count, ToastStore.maxToasts)
        XCTAssertFalse(store.toasts.contains { $0.kind == .bell }, "en eski (bell) düştü")

        store.show(.bell, title: "bell", message: "", terminalID: id)
        XCTAssertTrue(store.toasts.contains { $0.kind == .bell }, "slot boşaldığı için tekrar gösterilir")
    }
}
