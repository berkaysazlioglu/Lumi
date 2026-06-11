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
        // Karar 5: spawn-limit aşımı dahil her hata görünür
        let store = ToastStore(autoDismissAfter: 60)
        store.reporting {
            throw LumiError.terminalLimitReached(max: 3)
        }
        XCTAssertEqual(store.toasts.count, 1)
        XCTAssertEqual(store.toasts.first?.kind, .error)
        XCTAssertTrue(store.toasts.first?.message.contains("3") == true)
    }

    func testReportingPassesThroughSuccess() {
        let store = ToastStore(autoDismissAfter: 60)
        store.reporting {}
        XCTAssertTrue(store.toasts.isEmpty)
    }
}
