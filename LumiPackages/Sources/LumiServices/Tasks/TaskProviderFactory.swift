import Foundation
import LumiKit

/// Canlı adapter fabrikası. `custom` adapter'ı protokol fazında (Faz 2) gelir;
/// o zamana kadar bağlanmayı açık bir mesajla reddeder.
public struct LiveTaskProviderFactory: TaskProviderMaking {
    public init() {}

    public func makeProvider(for source: TaskSource, token: String?) -> any TaskProviding {
        switch source.kind {
        case .demo: DemoTaskProvider()
        case .custom, .github, .linear: UnavailableTaskProvider(kind: source.kind)
        }
    }
}

/// Henüz yazılmamış adapter: her çağrı aynı açıklayıcı hatayı fırlatır.
public struct UnavailableTaskProvider: TaskProviding {
    let kind: TaskProviderKind

    public init(kind: TaskProviderKind) {
        self.kind = kind
    }

    private var error: TaskProviderError {
        .unsupported("\(kind.title) connections in this build — protocol support arrives in the next phase")
    }

    public func discover() async throws -> TaskSourceInfo { throw error }
    public func listTasks() async throws -> [TaskItem] { throw error }
    public func update(taskID: String, patch: TaskPatch) async throws -> TaskItem { throw error }
    public func create(_ draft: TaskDraft) async throws -> TaskItem { throw error }
    public func delete(taskID: String) async throws { throw error }
    public func listUsers() async throws -> [TaskUser] { throw error }
    public func listProjects() async throws -> [TaskProjectRef] { throw error }
}
