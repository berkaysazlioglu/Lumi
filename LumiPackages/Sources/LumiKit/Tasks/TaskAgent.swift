import Foundation

/// Task'i bir ajana verme (Tasks planı: "Task → ajan").
///
/// Task Lumi'de bir prompt gibidir: `Start` seçilen checkout'ta normal,
/// görünür bir ajan terminali açar. Ajan işi bitirip doğruladığında Lumi'nin
/// MCP aracı `submit_for_review`'u çağırır ve task kendiliğinden In Review'a
/// geçer. Done'a yalnız insan taşır.

/// Ajanın nerede çalışacağı.
public enum TaskCheckoutChoice: Sendable, Hashable {
    /// Projenin mevcut bir checkout'u (kök ya da workspace).
    case existing(path: String)
    /// Task'e özel yeni workspace (git worktree) — paralel task'ler birbirine
    /// dokunmaz.
    case newWorkspace(projectPath: String, branch: String)

    public var label: String {
        switch self {
        case .existing(let path): (path as NSString).lastPathComponent
        case .newWorkspace(_, let branch): branch
        }
    }
}

/// Hangi ajan ve model.
public struct TaskAgentChoice: Sendable, Hashable {
    /// `nil` = Claude'un varsayılan modeli (karar 121'in takma adları dışında).
    public var model: ClaudeModelAlias?

    public init(model: ClaudeModelAlias? = nil) {
        self.model = model
    }

    public var title: String {
        model.map { "Claude \($0.displayName)" } ?? "Claude"
    }
}

/// `Start` isteği.
public struct TaskAgentRequest: Sendable, Hashable {
    public let task: TaskKey
    public let taskTitle: String
    public let checkout: TaskCheckoutChoice
    public let agent: TaskAgentChoice
    public let prompt: String

    public init(task: TaskKey, taskTitle: String, checkout: TaskCheckoutChoice, agent: TaskAgentChoice, prompt: String) {
        self.task = task
        self.taskTitle = taskTitle
        self.checkout = checkout
        self.agent = agent
        self.prompt = prompt
    }
}

/// Bağlı ajanın durumu — kartta ve detayda gösterilir.
public enum TaskAgentState: Sendable, Hashable {
    case starting
    /// Ajan turn'ünde çalışıyor.
    case working
    /// Ajan durdu ve kullanıcıdan bir şey bekliyor (izin, soru).
    case needsInput
    /// Turn bitti ama ajan `submit_for_review` çağırmadı — kullanıcı karar verir.
    case idle
    /// Ajan işi teslim etti; task In Review'a taşındı.
    case submitted(summary: String)
    /// Terminal kapandı.
    case exited

    public var title: String {
        switch self {
        case .starting: "Starting"
        case .working: "Working"
        case .needsInput: "Needs input"
        case .idle: "Waiting"
        case .submitted: "Submitted for review"
        case .exited: "Exited"
        }
    }

    public var isActive: Bool {
        switch self {
        case .starting, .working, .needsInput, .idle: true
        case .submitted, .exited: false
        }
    }
}

/// Task ↔ ajan bağlantısı.
public struct TaskAgentLink: Sendable, Hashable {
    public let task: TaskKey
    public let agent: TaskAgentChoice
    public let checkout: TaskCheckoutChoice
    public var state: TaskAgentState
    public let startedAt: Date
    /// Gerçek terminal (Faz 3); önizleme koşucusunda nil.
    public var terminalID: TerminalID?

    public init(
        task: TaskKey,
        agent: TaskAgentChoice,
        checkout: TaskCheckoutChoice,
        state: TaskAgentState = .starting,
        startedAt: Date,
        terminalID: TerminalID? = nil
    ) {
        self.task = task
        self.agent = agent
        self.checkout = checkout
        self.state = state
        self.startedAt = startedAt
        self.terminalID = terminalID
    }
}

/// Koşucunun bildirdiği olaylar.
public enum TaskAgentEvent: Sendable, Hashable {
    case started(TerminalID?)
    case state(TaskAgentState)
}

/// Ajanı başlatan dikiş. Faz 3'te gerçek terminal + MCP ile yazılır; o zamana
/// kadar önizleme koşucusu durumu taklit eder.
public protocol TaskAgentRunning: Sendable {
    /// Gerçek terminal açıyor mu — önizleme koşucusu `false` döner, UI bunu
    /// "Preview" rozetiyle söyler.
    var isPreview: Bool { get }
    func start(_ request: TaskAgentRequest) -> AsyncStream<TaskAgentEvent>
}

/// Ajana verilen prompt'un şablonu.
public enum TaskAgentPrompt {
    /// MCP aracının adı — prompt ve sunucu aynı kaynaktan okur.
    public static let submitTool = "submit_for_review"

    public static func make(task: TaskItem, includeBody: Bool) -> String {
        var lines = ["Work on task \(task.id): \(task.title)"]
        if includeBody, let body = task.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            lines += ["", body]
        }
        lines += [
            "",
            "When the work is complete and verified (builds, tests), call the `\(submitTool)` tool from the lumi MCP server with a short summary of what you changed. That moves the task to In Review. Never mark it done yourself.",
        ]
        return lines.joined(separator: "\n")
    }

    /// Yeni workspace için dal adı önerisi: `task/<id>-<başlıktan slug>`.
    public static func branchName(for task: TaskItem) -> String {
        let slug = task.title.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { result, character in
                if character == "-", result.last == "-" { return }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let id = task.id.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let trimmedSlug = String(slug.prefix(32)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "task/" + String(id) + (trimmedSlug.isEmpty ? "" : "-" + trimmedSlug)
    }
}

/// Task'in projesini Lumi projesiyle eşleştirme (Faz 3'te git origin'i de
/// katılır). Şimdilik ad: proje anahtarı ya da adı, klasör adıyla büyük-küçük
/// harf duyarsız eşleşir; tek aday varsa.
public enum TaskProjectMatcher {
    public static func match(_ project: TaskProjectRef?, in projectPaths: [String]) -> String? {
        guard let project else { return nil }
        let wanted = Set([project.key, project.name].compactMap { $0?.lowercased() })
        let candidates = projectPaths.filter { wanted.contains(($0 as NSString).lastPathComponent.lowercased()) }
        return candidates.count == 1 ? candidates[0] : nil
    }
}

/// Görsel indirme/önbellek dikişi. Görünümler servisi görmez; store bunun
/// üstünden yerel dosya ister.
public protocol TaskImageLoading: Sendable {
    /// Görselin yerel kopyası — önbellekte varsa ağa çıkmaz. `authorization`
    /// yalnız kaynağın kendi sunucusundaki adreslere gönderilir (Faz 2).
    func localFile(for url: URL, authorization: String?) async throws -> URL
}
