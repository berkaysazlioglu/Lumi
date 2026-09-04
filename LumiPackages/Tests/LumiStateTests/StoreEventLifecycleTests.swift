import Foundation
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiState

/// start/stop simetrisi (refactor plan 2.5 + 3.4 `StoreLifecycle` ön koşulu):
/// **`stop()` sonrası gelen event state'i DEĞİŞTİRMEZ.** Bugün üç farklı kalıp
/// var (start/stop, update/stop, hiçbiri); refactor bunları tekilleştirirken bu
/// testler kılavuz olur.
///
/// `RepoStore` ve `SettingsStore` karşılıkları kendi test dosyalarındadır.
@MainActor
final class StoreEventLifecycleTests: XCTestCase {
    private func waitUntil(
        _ description: String,
        _ condition: @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(2)
        while await !condition() {
            if Date() > deadline { return XCTFail("koşul sağlanmadı: \(description)") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func makeTerminal(repo: String = "/repo") -> TerminalMeta {
        TerminalMeta(id: TerminalID(), name: "t", repoPath: repo, createdAt: Date())
    }

    // MARK: - TerminalListStore

    func testTerminalListStoreConsumesEventsAfterStart() async throws {
        let service = FakeTerminalService()
        let store = TerminalListStore(service: service, toasts: ToastStore(autoDismissAfter: 60))
        defer { store.stop() }

        store.start()
        service.emit(.spawned(makeTerminal()))
        try await waitUntil("spawn tüketildi") { store.totalCount == 1 }
    }

    func testTerminalListStoreIgnoresEventsAfterStop() async throws {
        let service = FakeTerminalService()
        let store = TerminalListStore(service: service, toasts: ToastStore(autoDismissAfter: 60))

        store.start()
        service.emit(.spawned(makeTerminal()))
        try await waitUntil("akış canlı") { store.totalCount == 1 }

        store.stop()
        service.emit(.spawned(makeTerminal()))
        service.emit(.spawned(makeTerminal()))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(store.totalCount, 1, "stop sonrası event state'i değiştirmez")
    }

    func testTerminalListStoreStartIsIdempotent() async throws {
        let service = FakeTerminalService()
        let store = TerminalListStore(service: service, toasts: ToastStore(autoDismissAfter: 60))
        defer { store.stop() }

        store.start()
        store.start()
        service.emit(.spawned(makeTerminal()))
        try await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(store.totalCount, 1, "iki tüketici olsaydı terminal iki kez eklenirdi")
    }

    func testTerminalListStoreStopThenStartResumes() async throws {
        let service = FakeTerminalService()
        let store = TerminalListStore(service: service, toasts: ToastStore(autoDismissAfter: 60))
        defer { store.stop() }

        store.start()
        store.stop()
        store.start()
        // DİKKAT (bulgu, düzeltilmedi — Faz 3.4 `StoreLifecycle`): `stop()`
        // eşzamanlı DEĞİL. Tüketici Task'ı henüz `for await`'a girmemişse iptal
        // gecikir; broadcaster continuation'ı da termination'a kadar kayıtlı
        // kalır. Bu pencerede emit edilen event ESKİ tüketici tarafından da
        // uygulanabilir (aynı event iki kez). Test o pencereyi kapatıp yalnız
        // "yeniden tüketim çalışıyor" sözleşmesini kilitler.
        try await Task.sleep(for: .milliseconds(30))
        service.emit(.spawned(makeTerminal()))
        try await waitUntil("yeniden tüketim") { store.totalCount == 1 }
    }

    // MARK: - PromptQueueStore

    private func makePromptQueue() -> (PromptQueueStore, FakeTerminalService) {
        let service = FakeTerminalService()
        let store = PromptQueueStore(
            service: service,
            toasts: ToastStore(autoDismissAfter: 60),
            settleDelay: .zero
        )
        return (store, service)
    }

    func testPromptQueueStoreConsumesStatusEventsAfterStart() async throws {
        let (store, service) = makePromptQueue()
        defer { store.stop() }
        let id = TerminalID()
        store.enqueue("hello", for: id)

        store.start()
        service.emit(.statusChanged(id, .waitingUnseen))
        try await waitUntil("enjeksiyon oldu") { service.writtenTexts.count == 1 }
        XCTAssertTrue(store.prompts(for: id).isEmpty)
    }

    /// Tüketicinin gerçekten `for await`'te askıda olduğunu kanıtlayan probe:
    /// bir enjeksiyon turu tamamlanmadan `stop()` çağrılırsa iptal penceresi
    /// yarışır (bkz. `testTerminalListStoreStopThenStartResumes` notu).
    private func establishLiveConsumer(
        _ store: PromptQueueStore,
        _ service: FakeTerminalService,
        _ id: TerminalID
    ) async throws {
        store.enqueue("probe", for: id)
        store.start()
        service.emit(.statusChanged(id, .waitingUnseen))
        try await waitUntil("probe enjekte edildi") { service.writtenTexts.count == 1 }
        // Kuyruk boşken working'e dön: sonraki `enqueue` kendi başına enjekte etmesin.
        service.emit(.statusChanged(id, .working))
        try await Task.sleep(for: .milliseconds(30))
    }

    func testPromptQueueStoreIgnoresStatusEventsAfterStop() async throws {
        let (store, service) = makePromptQueue()
        let id = TerminalID()
        try await establishLiveConsumer(store, service, id)

        store.stop()
        store.enqueue("queued", for: id)
        XCTAssertEqual(service.writtenTexts.count, 1, "working durumunda enqueue enjekte etmez")

        service.emit(.statusChanged(id, .waitingUnseen))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(service.writtenTexts.count, 1, "stop sonrası status event'i enjeksiyon tetiklemez")
        XCTAssertEqual(store.prompts(for: id), ["queued"], "kuyruk olduğu gibi kalır")
    }

    func testPromptQueueStoreIgnoresExitEventAfterStop() async throws {
        let (store, service) = makePromptQueue()
        let id = TerminalID()
        try await establishLiveConsumer(store, service, id)
        store.enqueue("queued", for: id)

        store.stop()
        service.emit(.exited(id, code: 0))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(store.prompts(for: id), ["queued"], "stop sonrası exit kuyruğu temizlemez")
    }

    func testPromptQueueStoreStopCancelsPendingSettleWork() async throws {
        let service = FakeTerminalService()
        // Uzun settle: stop, bekleyen enjeksiyonu iptal etmeli.
        let store = PromptQueueStore(
            service: service,
            toasts: ToastStore(autoDismissAfter: 60),
            settleDelay: .milliseconds(300)
        )
        let id = TerminalID()
        store.enqueue("hello", for: id)
        store.start()
        service.emit(.statusChanged(id, .waitingUnseen))
        try await Task.sleep(for: .milliseconds(40)) // settle penceresi içindeyiz

        store.stop()
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertTrue(service.writtenTexts.isEmpty, "stop bekleyen settle task'ını iptal eder")
        XCTAssertEqual(store.prompts(for: id), ["hello"])
    }

    func testPromptQueueStoreStartIsIdempotent() async throws {
        let (store, service) = makePromptQueue()
        defer { store.stop() }
        let id = TerminalID()
        store.enqueue("a", for: id)
        store.enqueue("b", for: id)

        store.start()
        store.start()
        service.emit(.statusChanged(id, .waitingUnseen))
        try await waitUntil("bir enjeksiyon") { service.writtenTexts.count >= 1 }
        try await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(service.writtenTexts.count, 1, "iki tüketici olsaydı iki prompt akardı")
    }
}
