import Foundation
import LumiKit
import Observation

@Observable
@MainActor
public final class AgentHistoryStore {
    public private(set) var entries: [String: [AgentHistoryEntry]] = [:]
    public private(set) var loading: Set<String> = []
    public private(set) var errors: [String: String] = [:]
    @ObservationIgnored private let service: any AgentHistoryReading
    @ObservationIgnored private var generations: [String: UUID] = [:]

    public init(service: any AgentHistoryReading) { self.service = service }

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
}
