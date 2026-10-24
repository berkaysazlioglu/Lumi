import Foundation

/// Adapter çağrısının adı — hata kaydında "ne yapılırken" sorusunun cevabı.
public enum TaskOperation: String, Sendable, Hashable, CaseIterable {
    case discover
    case listTasks
    case update
    case create
    case delete
    case listUsers
    case listProjects
    case loadImage

    public var title: String {
        switch self {
        case .discover: "Discovery"
        case .listTasks: "List tasks"
        case .update: "Update task"
        case .create: "Create task"
        case .delete: "Delete task"
        case .listUsers: "List users"
        case .listProjects: "List projects"
        case .loadImage: "Load image"
        }
    }
}

/// Başarısız bir kaynak isteğinin ayrıntılı kaydı (Tasks planı: "Hatalar").
///
/// Amaç sunucuyu yazan kişinin (ya da ajanın) hatayı tek bakışta düzeltmesi:
/// hangi istek, hangi HTTP durumu, sunucunun kendi hata kodu/mesajı ve
/// yanıtın başı. HTTP adapter'ı (Faz 2) bunu doğrudan fırlatır; diğer
/// hatalar `TaskRequestFailure.from` ile sarılır. Token ASLA girmez.
public struct TaskRequestFailure: Error, Sendable, Hashable, Identifiable, LocalizedError {
    public let id: UUID
    public let kind: TaskProviderError
    public let operation: TaskOperation
    /// `PATCH /lumi/v1/tasks/DEMO-1` gibi; adapter HTTP değilse nil.
    public let request: String?
    public let httpStatus: Int?
    /// Sunucunun hata zarfındaki `error.code` / `error.message`.
    public let serverCode: String?
    public let serverMessage: String?
    /// Ham yanıtın ilk birkaç yüz karakteri (zarf bozuksa tek ipucu budur).
    public let responseExcerpt: String?
    /// İlgili task (yazımlarda).
    public let taskID: String?
    public let at: Date

    public static let excerptLimit = 600

    public init(
        kind: TaskProviderError,
        operation: TaskOperation,
        request: String? = nil,
        httpStatus: Int? = nil,
        serverCode: String? = nil,
        serverMessage: String? = nil,
        responseExcerpt: String? = nil,
        taskID: String? = nil,
        at: Date = Date(),
        id: UUID = UUID()
    ) {
        self.id = id
        self.kind = kind
        self.operation = operation
        self.request = request
        self.httpStatus = httpStatus
        self.serverCode = serverCode
        self.serverMessage = serverMessage
        self.responseExcerpt = responseExcerpt.map { String($0.prefix(Self.excerptLimit)) }
        self.taskID = taskID
        self.at = at
    }

    /// Herhangi bir hatayı kayda çevirir; zaten kayıtsa işlem/task bilgisi
    /// eksikse tamamlanır.
    public static func from(_ error: any Error, operation: TaskOperation, taskID: String? = nil, at: Date = Date()) -> TaskRequestFailure {
        if let failure = error as? TaskRequestFailure { return failure }
        let kind = error as? TaskProviderError
            ?? .unreachable((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        return TaskRequestFailure(kind: kind, operation: operation, taskID: taskID, at: at)
    }

    /// Kısa, tek satırlık özet — toast mesajı.
    public var summary: String {
        var parts: [String] = []
        if let httpStatus { parts.append("HTTP \(httpStatus)") }
        if let serverCode { parts.append(serverCode) }
        let message = serverMessage ?? kind.errorDescription ?? ""
        return parts.isEmpty ? message : parts.joined(separator: " · ") + " — " + message
    }

    public var errorDescription: String? { summary }

    /// Düzeltme ipucu: protokolün bu durumda ne beklediği.
    public var hint: String {
        switch kind {
        case .unauthorized:
            "The server rejected the Bearer token. Check that LUMI_TASKS_TOKEN on the server matches the token saved in Lumi."
        case .notFound:
            "The server answered 404. If the task exists, check the route: \(request ?? "the endpoint") must match the Lumi Tasks Protocol path."
        case .unsupported:
            "The server didn't declare this capability in GET /lumi/v1, or answered 405/501."
        case .unsupportedVersion:
            "GET /lumi/v1 must return \"version\": 1."
        case .conflict:
            "The task changed on the server since Lumi last read it (409). Lumi reloads it automatically."
        case .unreachable:
            "Lumi couldn't reach the server. Check the address, that the app is running, and HTTPS."
        case .invalidResponse:
            "The response didn't match the protocol. Errors must use { \"error\": { \"code\", \"message\" } } and successful responses the documented JSON shape."
        }
    }

    /// Ajana yapıştırılacak ayrıntılı rapor (Verify raporuyla aynı amaç).
    public var agentReport: String {
        var lines = ["Lumi Tasks request failed — please fix the server:", ""]
        lines.append("- Operation: \(operation.title)")
        if let request { lines.append("- Request: \(request)") }
        if let taskID { lines.append("- Task: \(taskID)") }
        if let httpStatus { lines.append("- HTTP status: \(httpStatus)") }
        if let serverCode { lines.append("- Server error code: \(serverCode)") }
        lines.append("- Message: \(serverMessage ?? kind.errorDescription ?? "")")
        lines.append("- Expected: \(hint)")
        if let responseExcerpt, !responseExcerpt.isEmpty {
            lines += ["", "Response body (first \(Self.excerptLimit) characters):", "```", responseExcerpt, "```"]
        }
        return lines.joined(separator: "\n")
    }
}

/// Demo kaynağın hata taklidi — "hatalar nasıl görünüyor" gözle denensin
/// diye. Gerçek adapter'lar bunu uygulamaz.
public enum TaskSimulatedFailure: String, CaseIterable, Sendable, Hashable {
    case rejectWrites
    case serverErrorOnList
    case unauthorized
    case offline

    public var title: String {
        switch self {
        case .rejectWrites: "Reject writes (422)"
        case .serverErrorOnList: "Server error on list (500)"
        case .unauthorized: "Reject token (401)"
        case .offline: "Server offline"
        }
    }
}

public protocol TaskProviderSimulating: Sendable {
    func setSimulatedFailure(_ failure: TaskSimulatedFailure?) async
}
