import Foundation
import LumiKit
import Observation

/// Uygulamanın tek hata lavabosu + toast kuyruğu (design/03 §4, spec/21 kuralları:
/// max 5, 5sn auto-dismiss, dedupe). Karar 5: kullanıcıyı etkileyen her hata
/// `reporting {}` koridorundan buraya düşer — hiçbir hata yalnız console'a gitmez.
@Observable
@MainActor
public final class ToastStore {
    public struct Toast: Identifiable, Equatable, Sendable {
        public enum Kind: Sendable, Equatable {
            case bell
            case error
            case success
            case info
        }

        public let id: UUID
        public let kind: Kind
        public let title: String
        public let message: String
        /// Bell toast'ları tıklanınca terminali (minimize ise restore edip) odaklar.
        public let terminalID: TerminalID?
    }

    public static let maxToasts = 5
    public static let defaultAutoDismiss: TimeInterval = 5

    public private(set) var toasts: [Toast] = []

    @ObservationIgnored private let autoDismissAfter: TimeInterval
    @ObservationIgnored private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    public init(autoDismissAfter: TimeInterval = ToastStore.defaultAutoDismiss) {
        self.autoDismissAfter = autoDismissAfter
    }

    public func show(
        _ kind: Toast.Kind,
        title: String,
        message: String = "",
        terminalID: TerminalID? = nil
    ) {
        // Dedupe: aynı içerik aktifken eklenmez; bell için terminal başına bir aktif
        // toast kuralı (spec/21 §17)
        let isDuplicate = toasts.contains { existing in
            if kind == .bell, existing.kind == .bell, let terminalID {
                return existing.terminalID == terminalID
            }
            return existing.kind == kind && existing.title == title && existing.message == message
        }
        guard !isDuplicate else { return }

        let toast = Toast(id: UUID(), kind: kind, title: title, message: message, terminalID: terminalID)
        toasts.append(toast)
        if toasts.count > Self.maxToasts {
            let dropped = toasts.removeFirst()
            dismissTasks.removeValue(forKey: dropped.id)?.cancel()
        }
        dismissTasks[toast.id] = Task { [autoDismissAfter, id = toast.id] in
            try? await Task.sleep(for: .seconds(autoDismissAfter))
            guard !Task.isCancelled else { return }
            self.dismiss(id)
        }
    }

    public func show(error: LumiError) {
        show(.error, title: "Error", message: error.localizedDescription)
    }

    public func dismiss(_ id: UUID) {
        toasts.removeAll { $0.id == id }
        dismissTasks.removeValue(forKey: id)?.cancel()
    }

    public func clearAll() {
        toasts.removeAll()
        dismissTasks.values.forEach { $0.cancel() }
        dismissTasks.removeAll()
    }

    // MARK: - Hata koridoru (karar 5)

    /// Dönüş: işlem hatasız tamamlandıysa true (başarıya bağlı akışlar için).
    @discardableResult
    public func reporting(_ operation: () throws -> Void) -> Bool {
        do {
            try operation()
            return true
        } catch let error as LumiError {
            show(error: error)
        } catch {
            show(error: .underlying(domain: "unknown", message: "\(error)"))
        }
        return false
    }

    @discardableResult
    public func reporting(_ operation: @MainActor () async throws -> Void) async -> Bool {
        do {
            try await operation()
            return true
        } catch let error as LumiError {
            show(error: error)
        } catch {
            show(error: .underlying(domain: "unknown", message: "\(error)"))
        }
        return false
    }
}
