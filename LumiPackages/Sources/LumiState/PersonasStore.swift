import Foundation
import LumiKit
import Observation

/// Persona listesi store'u (pull-after-push: changed → yeniden çek).
@Observable
@MainActor
public final class PersonasStore {
    public private(set) var personas: [Persona] = []

    @ObservationIgnored private let service: any PersonaServicing
    @ObservationIgnored private let toasts: ToastStore
    @ObservationIgnored private var consumeTask: Task<Void, Never>?
    @ObservationIgnored private var currentProjectPath: String?

    public init(service: any PersonaServicing, toasts: ToastStore) {
        self.service = service
        self.toasts = toasts
    }

    public func start() {
        guard consumeTask == nil else { return }
        consumeTask = Task { @MainActor [weak self, service] in
            let stream = await service.events()
            await self?.reload()
            for await _ in stream {
                await self?.reload()
            }
        }
    }

    public func stop() {
        consumeTask?.cancel()
        consumeTask = nil
    }

    /// Aktif tab değişiminde project scope'u takip eder.
    public func setProject(_ projectPath: String?) async {
        currentProjectPath = projectPath
        await reload()
    }

    public func reload() async {
        personas = await service.personas(projectPath: currentProjectPath)
    }

    public func spawn(_ personaID: String, repoPath: String) {
        Task { @MainActor in
            await toasts.reporting {
                _ = try await self.service.spawn(personaID: personaID, repoPath: repoPath)
            }
        }
    }
}
