import Foundation

/// Tek tüketicili `AsyncStream` döngüsünün yaşam döngüsü (refactor 3.4).
///
/// İki kuralı yapısal olarak garanti eder:
///
/// 1. **Stream Task'tan ÖNCE alınır.** Çağıran `service.events()`'i senkron
///    çağırıp buraya verir; abonelik `start()` döndüğünde kuruludur, boot
///    penceresinde event kaybolmaz (plan 5.6).
/// 2. **`stop()` eşzamanlıdır.** `Task.cancel()` yalnızca *isteği* iletir:
///    tüketici `for await`'te askıdaysa iptal bir sonraki tura kadar
///    görülmez, bu pencerede gelen event ESKİ tüketici tarafından uygulanabilir
///    (start-stop-start'ta aynı event iki kez). Nesil (generation) sayacı bunu
///    kapatır: `stop()` nesli ilerletir, eski tüketici uyandığında neslini
///    doğrulayamaz ve hiçbir mutasyon uygulamadan çıkar. `stop()` MainActor'da
///    koştuğu için döndüğü anda garanti yürürlüktedir.
@MainActor
public final class EventConsumer {
    private var task: Task<Void, Never>?
    private var generation = 0

    public init() {}

    public var isRunning: Bool { task != nil }

    /// Idempotent başlatma. `prologue` ilk event'ten önce koşar (ör. ilk
    /// yükleme); nesil kontrolü prologue'dan sonra da yapılır.
    ///
    /// `stream` `@autoclosure`'dır: idempotence kontrolünden SONRA, ama Task
    /// kurulmadan ÖNCE senkron değerlendirilir. Argüman olarak geçseydi ikinci
    /// `start()` çağrısı tüketmeyeceği bir abonelik daha açardı.
    public func start<Event: Sendable>(
        _ stream: @autoclosure () -> AsyncStream<Event>,
        prologue: (@MainActor () async -> Void)? = nil,
        handle: @escaping @MainActor (Event) async -> Void
    ) {
        guard task == nil else { return }
        let stream = stream()
        generation += 1
        let epoch = generation
        task = Task { @MainActor [weak self] in
            await prologue?()
            guard self?.generation == epoch else { return }
            for await event in stream {
                guard self?.generation == epoch else { return }
                // `await`: event işleme SERİdir — bir tur bitmeden sonraki
                // event işlenmez (repo reload'larının sırası bu garantiye bağlı).
                await handle(event)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        // Nesil ilerlemesi iptalin gecikmesini telafi eder (bkz. tip yorumu).
        generation += 1
    }
}
