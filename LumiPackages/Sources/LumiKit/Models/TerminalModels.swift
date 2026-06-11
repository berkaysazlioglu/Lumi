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
}

/// AI sağlayıcısı (config seviyesi; spec/13).
public enum AgentProvider: String, Sendable, Codable, Equatable {
    case claude
    case codex
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

    public init(
        id: TerminalID,
        name: String,
        repoPath: String,
        createdAt: Date,
        task: String? = nil,
        oscTitle: String? = nil,
        status: TerminalStatus = .idle
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.createdAt = createdAt
        self.task = task
        self.oscTitle = oscTitle
        self.status = status
    }
}

/// Terminal servisinin yayınladığı yaşam döngüsü event'leri.
/// Ham çıktı event değildir — PTY→emülatör hattında LumiTerminal içinde akar.
public enum TerminalEvent: Sendable, Equatable {
    case spawned(TerminalMeta)
    case exited(TerminalID, code: Int32)
    case statusChanged(TerminalID, TerminalStatus)
    case titleChanged(TerminalID, String)
    case bell(TerminalID)
}
