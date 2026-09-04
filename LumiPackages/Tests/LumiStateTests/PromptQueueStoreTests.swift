import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiState

@MainActor
final class PromptQueueStoreTests: XCTestCase {
    private func makeStore() -> (PromptQueueStore, FakeTerminalService) {
        let service = FakeTerminalService()
        // settle=0 → testlerde deterministik: pendingInjection await edilir.
        let store = PromptQueueStore(
            service: service,
            toasts: ToastStore(autoDismissAfter: 60),
            settleDelay: .zero
        )
        return (store, service)
    }

    // MARK: - İlgisiz event'ler

    func testViewFocusedEventDoesNotDisturbQueue() {
        // Arrange
        let (store, _) = makeStore()
        let id = TerminalID()
        store.enqueue("a", for: id)

        // Act — odak event'i kuyruk semantiğini etkilemez
        store.apply(.viewFocused(id))

        // Assert
        XCTAssertEqual(store.prompts(for: id), ["a"])
        XCTAssertFalse(store.isPaused(id))
    }

    // MARK: - CRUD

    func testEnqueueTrimsAndIgnoresEmpty() {
        let (store, _) = makeStore()
        let id = TerminalID()
        store.enqueue("  hello  ", for: id)
        store.enqueue("   ", for: id)
        XCTAssertEqual(store.prompts(for: id), ["hello"])
    }

    func testRemoveAndClear() {
        let (store, _) = makeStore()
        let id = TerminalID()
        store.enqueue("a", for: id)
        store.enqueue("b", for: id)
        store.remove(at: 0, for: id)
        XCTAssertEqual(store.prompts(for: id), ["b"])
        store.clear(for: id)
        XCTAssertEqual(store.count(for: id), 0)
    }

    func testMoveReorders() {
        let (store, _) = makeStore()
        let id = TerminalID()
        ["a", "b", "c"].forEach { store.enqueue($0, for: id) }
        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0, for: id)
        XCTAssertEqual(store.prompts(for: id), ["c", "a", "b"])
    }

    // MARK: - canInject predikatı

    func testCannotInjectWhenWorking() {
        let (store, _) = makeStore()
        let id = TerminalID()
        store.enqueue("a", for: id)
        store.apply(.statusChanged(id, .working))
        XCTAssertFalse(store.canInject(id))
    }

    func testCanInjectWhenWaiting() {
        let (store, _) = makeStore()
        let id = TerminalID()
        store.enqueue("a", for: id)
        store.apply(.statusChanged(id, .waitingSeen))
        XCTAssertTrue(store.canInject(id))
    }

    func testCannotInjectWhenEmpty() {
        let (store, _) = makeStore()
        let id = TerminalID()
        store.apply(.statusChanged(id, .waitingSeen))
        XCTAssertFalse(store.canInject(id))
    }

    func testCannotInjectWhenPaused() {
        let (store, _) = makeStore()
        let id = TerminalID()
        store.enqueue("a", for: id)
        store.apply(.statusChanged(id, .waitingSeen))
        store.setPaused(true, for: id)
        XCTAssertFalse(store.canInject(id))
    }

    func testCannotInjectWhenAwaitingDecision() {
        let (store, _) = makeStore()
        let id = TerminalID()
        store.enqueue("a", for: id)
        store.apply(.statusChanged(id, .waitingSeen))
        store.apply(.awaitingDecisionChanged(id, true))
        XCTAssertFalse(store.canInject(id))
    }

    // MARK: - injectHead

    func testInjectHeadWritesBracketedPasteAndPops() {
        let (store, service) = makeStore()
        let id = TerminalID()
        store.enqueue("first", for: id)
        store.enqueue("second", for: id)
        store.injectHead(id)
        XCTAssertEqual(service.writtenTexts.count, 1)
        XCTAssertEqual(service.writtenTexts.first?.text, PromptInjection.encode("first"))
        XCTAssertEqual(store.prompts(for: id), ["second"])
    }

    // MARK: - Tetikleme (deterministik await)

    func testWaitingTransitionInjectsHead() async {
        let (store, service) = makeStore()
        let id = TerminalID()
        store.enqueue("go", for: id)
        store.apply(.statusChanged(id, .waitingSeen))
        await store.pendingInjection(for: id)?.value
        XCTAssertEqual(service.writtenTexts.first?.text, PromptInjection.encode("go"))
        XCTAssertEqual(store.count(for: id), 0)
    }

    func testPermissionDuringSettleCancelsInjection() async {
        let (store, service) = makeStore()
        let id = TerminalID()
        store.enqueue("go", for: id)
        store.apply(.statusChanged(id, .waitingSeen))
        // settle penceresinde izin sinyali gelir → enjeksiyon iptal.
        store.apply(.awaitingDecisionChanged(id, true))
        await store.pendingInjection(for: id)?.value
        XCTAssertTrue(service.writtenTexts.isEmpty)
        XCTAssertEqual(store.prompts(for: id), ["go"])
    }

    func testExitClearsQueue() {
        let (store, _) = makeStore()
        let id = TerminalID()
        store.enqueue("a", for: id)
        store.apply(.exited(id, code: 0))
        XCTAssertEqual(store.count(for: id), 0)
    }

    // MARK: - Başarısız yazım (karar 5: sessiz yutma yok)

    func testRepeatedInjectFailuresRaiseSingleToastAndKeepQueue() {
        let service = FakeTerminalService()
        service.failWrites = true
        let toasts = ToastStore(autoDismissAfter: 60)
        let store = PromptQueueStore(service: service, toasts: toasts, settleDelay: .zero)
        let id = TerminalID()
        store.enqueue("go", for: id)

        for _ in 0..<PromptQueueStore.injectFailureToastThreshold {
            store.injectHead(id)
        }

        XCTAssertEqual(store.prompts(for: id), ["go"], "kuyruk korunur")
        XCTAssertEqual(toasts.toasts.count, 1, "eşikte bir kez toast")

        // Eşik geçildikten sonra tekrar tekrar toast basılmaz.
        store.injectHead(id)
        XCTAssertEqual(toasts.toasts.count, 1)
    }

    func testInjectFailuresBelowThresholdStaySilent() {
        let service = FakeTerminalService()
        service.failWrites = true
        let toasts = ToastStore(autoDismissAfter: 60)
        let store = PromptQueueStore(service: service, toasts: toasts, settleDelay: .zero)
        let id = TerminalID()
        store.enqueue("go", for: id)

        for _ in 0..<(PromptQueueStore.injectFailureToastThreshold - 1) {
            store.injectHead(id)
        }

        XCTAssertTrue(toasts.toasts.isEmpty, "geçici hatalar kullanıcıyı rahatsız etmez")
    }

    func testSuccessfulInjectResetsFailureCounter() {
        let (store, _) = makeStore()
        let id = TerminalID()
        store.enqueue("go", for: id)
        store.injectHead(id)
        XCTAssertEqual(store.consecutiveInjectFailures(for: id), 0)
    }
}
