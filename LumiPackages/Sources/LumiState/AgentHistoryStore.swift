import Foundation
import LumiKit
import Observation

@Observable
@MainActor
public final class AgentHistoryStore {
    public private(set) var entries: [String: [AgentHistoryEntry]] = [:]
    public private(set) var loading: Set<String> = []
    public private(set) var errors: [String: String] = [:]
    /// Dışa/içe aktarım sürüyor (düğmeler kapanır).
    public private(set) var isTransferring = false
    @ObservationIgnored private let service: any AgentHistoryServicing
    @ObservationIgnored private let transfer: any AgentSessionTransferring
    @ObservationIgnored private let toasts: ToastStore
    @ObservationIgnored private var generations: [String: UUID] = [:]

    public init(
        service: any AgentHistoryServicing,
        transfer: any AgentSessionTransferring,
        toasts: ToastStore
    ) {
        self.service = service
        self.transfer = transfer
        self.toasts = toasts
    }

    public func refresh(_ projectPath: String) async {
        guard !loading.contains(projectPath) else { return }
        let generation = UUID()
        generations[projectPath] = generation
        loading.insert(projectPath)
        defer {
            if generations[projectPath] == generation { loading.remove(projectPath) }
        }
        do {
            let result = try await service.entries(projectPath: projectPath)
            guard !Task.isCancelled, generations[projectPath] == generation else { return }
            entries[projectPath] = result
            errors.removeValue(forKey: projectPath)
        } catch {
            guard !Task.isCancelled, generations[projectPath] == generation else { return }
            errors[projectPath] = error.localizedDescription
        }
    }

    public func evict(_ projectPath: String) {
        generations.removeValue(forKey: projectPath)
        entries.removeValue(forKey: projectPath)
        errors.removeValue(forKey: projectPath)
        loading.remove(projectPath)
    }

    // MARK: - Silme (karar 53)

    /// Oturumu diskten kaldırır ve listeyi yeniler. Onay dialogu çağırandadır.
    @discardableResult
    public func deleteSession(_ entry: AgentHistoryEntry, projectPath: String) async -> Bool {
        guard !isTransferring else { return false }
        isTransferring = true
        let succeeded = await toasts.reporting { try await service.deleteSession(entry) }
        isTransferring = false
        guard succeeded else { return false }
        toasts.show(.success, title: "Session deleted", message: entry.title)
        await refresh(projectPath)
        return true
    }

    // MARK: - Dışa / içe aktarım (karar 52)

    /// Oturumu `destination`a paketler; sonuç toast'la bildirilir.
    @discardableResult
    public func exportSession(_ entry: AgentHistoryEntry, to destination: URL) async -> Bool {
        guard !isTransferring else { return false }
        isTransferring = true
        defer { isTransferring = false }
        let succeeded = await toasts.reporting { try await transfer.exportSession(entry, to: destination) }
        if succeeded {
            toasts.show(.success, title: "Session exported", message: destination.lastPathComponent)
        }
        return succeeded
    }

    /// Paketi `projectPath` için içe alır ve listeyi yeniler.
    @discardableResult
    public func importSession(from source: URL, projectPath: String) async -> AgentSessionImportResult? {
        guard !isTransferring else { return nil }
        isTransferring = true
        var result: AgentSessionImportResult?
        let succeeded = await toasts.reporting {
            result = try await transfer.importSession(from: source, projectPath: projectPath)
        }
        isTransferring = false
        guard succeeded, let result else { return nil }
        let renamed = result.didRenameSession ? " (renamed: a session with the same ID already existed)" : ""
        let subagents = result.subagentCount > 0 ? " with \(result.subagentCount) subagent(s)" : ""
        toasts.show(.success, title: "Session imported", message: "\(result.provider.rawValue.capitalized) session\(subagents)\(renamed)")
        await refresh(projectPath)
        return result
    }
}
