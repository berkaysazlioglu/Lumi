import Foundation

/// Telefondaki Tasks (karar 137, mobil ek): telefon kullanıcının task
/// sunucusuyla hiç konuşmaz; Mac'teki `TasksStore`'a relay üzerinden komut
/// gönderir. Bu dikiş `RemoteCommandHandler`'ı (LumiRemote — store'u
/// göremez) LumiAppCore'daki köprüye bağlar.
@MainActor
public protocol RemoteTasksHandling: AnyObject {
    /// `action`: `tasks_subscribe`, `tasks_unsubscribe`, `task_move`,
    /// `task_assign`, `task_create`, `task_detail`, `task_start`.
    func handleTaskCommand(action: String, payload: [String: Any]) async -> RemoteTaskCommandOutcome
}

public struct RemoteTaskCommandOutcome: Sendable, Equatable {
    public let ok: Bool
    public let error: String?
    /// Komuta özel düz alanlar (ör. `task_detail` → `body`).
    public let data: [String: String]?

    public init(ok: Bool, error: String? = nil, data: [String: String]? = nil) {
        self.ok = ok
        self.error = error
        self.data = data
    }

    public static let success = RemoteTaskCommandOutcome(ok: true)

    public static func failure(_ error: String) -> RemoteTaskCommandOutcome {
        RemoteTaskCommandOutcome(ok: false, error: error)
    }

    /// Telefondan gelen task komutu mu (`task_` / `tasks_` önekli).
    public static func isTaskAction(_ action: String) -> Bool {
        action.hasPrefix("task_") || action.hasPrefix("tasks_")
    }
}
