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
    }

    public static let maxToasts = 5
    public static let defaultAutoDismiss: TimeInterval = 5

    public private(set) var toasts: [Toast] = []

    @ObservationIgnored private let autoDismissAfter: TimeInterval
    @ObservationIgnored private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    public init(autoDismissAfter: TimeInterval = ToastStore.defaultAutoDismiss) {
        self.autoDismissAfter = autoDismissAfter
    }

    public func show(_ kind: Toast.Kind, title: String, message: String = "") {
        let isDuplicate = toasts.contains {
            $0.kind == kind && $0.title == title && $0.message == message
        }
        guard !isDuplicate else { return }

        let toast = Toast(id: UUID(), kind: kind, title: title, message: message)
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

    public func reporting(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch let error as LumiError {
            show(error: error)
        } catch {
            show(error: .underlying(domain: "unknown", message: "\(error)"))
        }
    }

    public func reporting(_ operation: @MainActor () async throws -> Void) async {
        do {
            try await operation()
        } catch let error as LumiError {
            show(error: error)
        } catch {
            show(error: .underlying(domain: "unknown", message: "\(error)"))
        }
    }
}
