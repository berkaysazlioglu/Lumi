import Foundation
import LumiKit
import Observation

/// Quick Action listesi + history cache (pull-after-push).
@Observable
@MainActor
public final class ActionsStore {
    public private(set) var actions: [Action] = []
    /// Context menüde senkron gösterim için reload'da doldurulur (ucuz dizin listesi).
    public private(set) var histories: [String: [ActionVersion]] = [:]

    @ObservationIgnored private let service: any ActionServicing
    @ObservationIgnored private let toasts: ToastStore
    @ObservationIgnored private var consumeTask: Task<Void, Never>?
    @ObservationIgnored private var currentProjectPath: String?

    public init(service: any ActionServicing, toasts: ToastStore) {
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

    public func setProject(_ projectPath: String?) async {
        currentProjectPath = projectPath
        await reload()
    }

    public func reload() async {
        let list = await service.actions(projectPath: currentProjectPath)
        var versionMap: [String: [ActionVersion]] = [:]
        for action in list where action.scope == .user {
            versionMap[action.id] = await service.history(actionID: action.id)
        }
        actions = list
        histories = versionMap
    }

    // MARK: - Intent'ler (hepsi hata koridorundan — karar 5)

    public func execute(_ actionID: String, repoPath: String) {
        Task { @MainActor in
            await toasts.reporting {
                _ = try await self.service.execute(actionID: actionID, repoPath: repoPath)
            }
        }
    }

    public func createNew(repoPath: String?) {
        Task { @MainActor in
            await toasts.reporting {
                _ = try await self.service.createNew(repoPath: repoPath)
            }
        }
    }

    public func edit(_ actionID: String, projectPath: String?) {
        Task { @MainActor in
            await toasts.reporting {
                _ = try await self.service.edit(actionID: actionID, projectPath: projectPath)
            }
        }
    }

    public func delete(_ actionID: String, scope: PresetScope, projectPath: String?) {
        Task { @MainActor in
            let succeeded = await toasts.reporting {
                try await self.service.delete(
                    actionID: actionID, scope: scope, projectPath: projectPath
                )
            }
            if succeeded {
                await self.reload()
            }
        }
    }

    public func restore(_ actionID: String, version: String) {
        Task { @MainActor in
            let succeeded = await toasts.reporting {
                try await self.service.restore(actionID: actionID, version: version)
            }
            if succeeded {
                await self.reload()
            }
        }
    }
}
