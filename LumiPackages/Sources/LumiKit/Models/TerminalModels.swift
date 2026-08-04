import Foundation

/// Terminal oturumunun benzersiz kimliği.
public struct TerminalID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let raw: UUID

    public init() {
        self.raw = UUID()
    }

    public init(raw: UUID) {
        self.raw = raw
    }

    public var description: String { raw.uuidString }
}

/// 6 durumlu, provider-agnostic terminal durumu (spec/10 §5).
/// Raw value'lar Electron'daki string'lerle birebir aynıdır (persistence/parite).
public enum TerminalStatus: String, Sendable, Codable, CaseIterable, Equatable {
    case idle
    case working
    case waitingUnseen = "waiting-unseen"
    case waitingFocused = "waiting-focused"
    case waitingSeen = "waiting-seen"
    case error

    /// Agent bir turn'ü bitirip girdi bekliyor (üç görünürlük varyantı).
    /// Prompt kuyruğu sıradaki prompt'u yalnız bu durumda gönderir.
    public var isWaiting: Bool {
        switch self {
        case .waitingUnseen, .waitingFocused, .waitingSeen: return true
        case .idle, .working, .error: return false
        }
    }
}

/// AI sağlayıcısı (config seviyesi; spec/13).
public enum AgentProvider: String, Sendable, Codable, Equatable, CaseIterable {
    case claude
    case codex

    /// UI etiketi (spec/20 §6: buton "New Claude"/"New Codex").
    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    /// Yeni provider terminalinde spawn sonrası enjekte edilen CLI komutu
    /// (spec/20 §6: önce shell açılır, sonra komut yazılır).
    public var launchCommand: String { rawValue }
}

/// Terminal metadata'sı — UI/state katmanının gördüğü tek model.
/// Ham çıktı ASLA burada taşınmaz (spec/00 §4.1-1); ekran modeli emülatörde yaşar.
public struct TerminalMeta: Sendable, Identifiable, Equatable {
    public let id: TerminalID
    public var name: String
    public let repoPath: String
    public let createdAt: Date
    public var task: String?
    public var oscTitle: String?
    public var status: TerminalStatus
    /// Karar 23: spawn komutuna enjekte edilen (veya komuttan çıkarılan) claude
    /// oturum kimliği — quit'te persist edilip açılışta resume için kullanılır.
    /// nil = bu terminal Lumi'nin izlediği bir claude oturumu taşımıyor.
    public let claudeSessionID: String?

    public init(
        id: TerminalID,
        name: String,
        repoPath: String,
        createdAt: Date,
        task: String? = nil,
        oscTitle: String? = nil,
        status: TerminalStatus = .idle,
        claudeSessionID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.createdAt = createdAt
        self.task = task
        self.oscTitle = oscTitle
        self.status = status
        self.claudeSessionID = claudeSessionID
    }
}

/// Terminal servisinin yayınladığı yaşam döngüsü event'leri.
/// Ham çıktı event değildir — PTY→emülatör hattında LumiTerminal içinde akar.
public enum TerminalEvent: Sendable, Equatable {
    case spawned(TerminalMeta)
    case exited(TerminalID, code: Int32)
    case statusChanged(TerminalID, TerminalStatus)
    case titleChanged(TerminalID, String)
    /// "Karar bekliyor" (izin promptu) sinyali — status'ten ayrı (spec/10).
    /// Prompt kuyruğu bunu görünce duraklar; renk/durum değişmez.
    case awaitingDecisionChanged(TerminalID, Bool)
    case bell(TerminalID)
}
