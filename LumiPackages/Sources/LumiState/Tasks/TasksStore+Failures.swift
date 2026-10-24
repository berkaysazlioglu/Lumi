import Foundation
import LumiKit

/// Hata kaydının satırı: hangi kaynakta ne oldu, kaç kez tekrarlandı.
public struct TaskFailureEntry: Identifiable, Sendable, Hashable {
    public let source: TaskSourceID
    public var failure: TaskRequestFailure
    /// Aynı hata art arda tekrarlandıysa (ör. her tazelemede 500) tek satırda sayılır.
    public var count: Int
    public var lastAt: Date

    public var id: UUID { failure.id }
}

/// Hata kaydı (Tasks planı: "Hatalar düzgün gösterilmeli").
///
/// Her başarısız istek ayrıntısıyla (istek satırı, HTTP durumu, sunucunun
/// hata kodu/mesajı, yanıtın başı) burada tutulur; toast yalnız özeti verir,
/// `Errors` sheet'i tamamını ve ajana yapıştırılacak raporu gösterir.
extension TasksStore {
    public static let failureLogLimit = 50

    @discardableResult
    func record(_ error: any Error, operation: TaskOperation, source: TaskSourceID, taskID: String? = nil) -> TaskRequestFailure {
        let failure = TaskRequestFailure.from(error, operation: operation, taskID: taskID, at: now())
        if let first = failureLog.first, first.source == source, Self.isSame(first.failure, failure) {
            failureLog[0].count += 1
            failureLog[0].lastAt = failure.at
            return failure
        }
        failureLog.insert(TaskFailureEntry(source: source, failure: failure, count: 1, lastAt: failure.at), at: 0)
        if failureLog.count > Self.failureLogLimit {
            failureLog.removeLast(failureLog.count - Self.failureLogLimit)
        }
        return failure
    }

    public func clearFailureLog() {
        failureLog.removeAll()
    }

    public func presentFailureLog() {
        isFailureLogPresented = true
    }

    /// Bir kaynağın son hatası — banttaki `Details` onu açar.
    public func lastFailure(in source: TaskSourceID) -> TaskFailureEntry? {
        failureLog.first { $0.source == source }
    }

    private static func isSame(_ lhs: TaskRequestFailure, _ rhs: TaskRequestFailure) -> Bool {
        lhs.operation == rhs.operation && lhs.request == rhs.request && lhs.httpStatus == rhs.httpStatus
            && lhs.serverCode == rhs.serverCode && lhs.summary == rhs.summary
    }
}

/// Görseller (Tasks planı: "Görseller") — görünümler servisi görmez, yerel
/// dosyayı store'dan ister.
extension TasksStore {
    public func imageFile(for image: URL, in source: TaskSourceID, task: String? = nil) async -> URL? {
        do {
            return try await images.localFile(for: image, authorization: providers[source]?.authorization(for: image))
        } catch {
            record(error, operation: .loadImage, source: source, taskID: task)
            return nil
        }
    }
}
