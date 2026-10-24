import Foundation
import LumiKit

/// Canlı adapter fabrikası: `custom` → Lumi Tasks Protocol üzerinden HTTP,
/// `demo` → bellek içi örnek veri. Henüz yazılmamış adapter'lar bağlanmayı
/// açık bir mesajla reddeder.
public struct LiveTaskProviderFactory: TaskProviderMaking {
    private let transport: any HTTPTransporting

    public init(transport: any HTTPTransporting = URLSessionTransport()) {
        self.transport = transport
    }

    public func makeProvider(for source: TaskSource, token: String?) -> any TaskProviding {
        switch source.kind {
        case .demo:
            return DemoTaskProvider()
        case .custom:
            guard let address = source.baseURL, case .success(let url) = TaskEndpoint.normalize(address) else {
                return UnavailableTaskProvider(kind: source.kind)
            }
            return LumiTasksHTTPProvider(baseURL: url, token: token, transport: transport)
        case .github, .linear:
            return UnavailableTaskProvider(kind: source.kind)
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
        .unsupported("\(kind.title) connections yet")
    }

    public func discover() async throws -> TaskSourceInfo { throw error }
    public func listTasks() async throws -> [TaskItem] { throw error }
    public func update(taskID: String, patch: TaskPatch) async throws -> TaskItem { throw error }
    public func create(_ draft: TaskDraft) async throws -> TaskItem { throw error }
    public func delete(taskID: String) async throws { throw error }
    public func listUsers() async throws -> [TaskUser] { throw error }
    public func listProjects() async throws -> [TaskProjectRef] { throw error }
}
