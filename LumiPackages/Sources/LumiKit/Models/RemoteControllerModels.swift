import Foundation

// Mac'ten Mac'e remote'un controller tarafı (docs/design/08-mac-remote.md).
// Tel biçimi LumiRemote'taki `RemoteControllerWire`'da çözülür; bu tipler UI'ın gördüğü hâlidir.

/// Relay directory'sindeki bir hub.
public struct RemoteHubInfo: Sendable, Equatable, Identifiable {
    public let id: String
    public var name: String
    public var isOnline: Bool
    public var lastSeenAt: Date?
    public var controllerCount: Int

    public init(id: String, name: String, isOnline: Bool, lastSeenAt: Date? = nil, controllerCount: Int = 0) {
        self.id = id
        self.name = name
        self.isOnline = isOnline
        self.lastSeenAt = lastSeenAt
        self.controllerCount = controllerCount
    }
}

/// Hub'daki bir terminal (telefonun `sessions` öğesi).
public struct RemoteSessionInfo: Sendable, Equatable, Identifiable {
    public let id: String
    public var title: String?
    public var repoName: String
    /// `TerminalStatus.rawValue` (`working`, `idle`, `waiting`…).
    public var status: String
    public var provider: AgentProvider?
    public var awaitingDecision: Bool
    public var lastActivityAt: Date?

    public init(
        id: String, title: String? = nil, repoName: String, status: String,
        provider: AgentProvider? = nil, awaitingDecision: Bool = false, lastActivityAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.repoName = repoName
        self.status = status
        self.provider = provider
        self.awaitingDecision = awaitingDecision
        self.lastActivityAt = lastActivityAt
    }
}

/// Hub'ın Projects ağacındaki bir checkout (kök / workspace / worktree).
public struct RemoteCheckoutNode: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let path: String
    public var title: String
    public var kind: String
    public var branch: String?
    public var agentIds: [String]

    public init(path: String, title: String, kind: String, branch: String? = nil, agentIds: [String] = []) {
        self.path = path
        self.title = title
        self.kind = kind
        self.branch = branch
        self.agentIds = agentIds
    }
}

public struct RemoteProjectNode: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let path: String
    public var name: String
    public var checkouts: [RemoteCheckoutNode]
    /// Proje kimlik rengi (karar 120, `ProjectColor.rawValue`) ve ikonu (`sf:…` / `emoji:…`).
    public var color: String?
    public var icon: String?

    public init(path: String, name: String, checkouts: [RemoteCheckoutNode], color: String? = nil, icon: String? = nil) {
        self.path = path
        self.name = name
        self.checkouts = checkouts
        self.color = color
        self.icon = icon
    }
}

/// Projects ▸ Other — projesiz terminaller dizinlerine göre (karar 108).
public struct RemoteOtherGroup: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let path: String
    public var label: String
    public var agentIds: [String]

    public init(path: String, label: String, agentIds: [String]) {
        self.path = path
        self.label = label
        self.agentIds = agentIds
    }
}

/// Bağlı bir hub'ın son bilinen hâli.
public struct RemoteHubSnapshot: Sendable, Equatable {
    public var sessions: [RemoteSessionInfo]
    public var projects: [RemoteProjectNode]
    public var others: [RemoteOtherGroup]

    public init(sessions: [RemoteSessionInfo] = [], projects: [RemoteProjectNode] = [], others: [RemoteOtherGroup] = []) {
        self.sessions = sessions
        self.projects = projects
        self.others = others
    }

    public func session(_ id: String) -> RemoteSessionInfo? {
        sessions.first { $0.id == id }
    }
}

/// Bir hub'a bağlantının durumu.
public enum RemoteHubLinkState: Sendable, Equatable {
    case disconnected
    /// Şifre doğrulanıyor / bağlanılıyor.
    case connecting
    case connected
    /// Hub şifreyi reddetti (`wrong_password`, `locked`…) — otomatik yeniden denenmez.
    case rejected(reason: String)
    /// Hub çevrimdışı; yeniden çevrimiçi olunca kendiliğinden bağlanılır.
    case waitingForHub

    public var isConnected: Bool { self == .connected }
}

/// Uzak terminal aynasına giden parça: `isSnapshot` ise emülatör baştan kurulur (scrollback).
public struct RemoteTerminalChunk: Sendable, Equatable {
    public let data: Data
    public let cols: Int?
    public let rows: Int?
    public let isSnapshot: Bool

    public init(data: Data, cols: Int? = nil, rows: Int? = nil, isSnapshot: Bool) {
        self.data = data
        self.cols = cols
        self.rows = rows
        self.isSnapshot = isSnapshot
    }
}

/// Hub'da açılacak terminalin türü.
public enum RemoteSessionKind: Sendable, Equatable {
    /// Claude (isteğe bağlı model kısayoluyla, karar 121/133).
    case claude(model: ClaudeModelAlias?)
    /// Düz shell.
    case shell
}

/// Uzak terminalin okunmuş hâli: Claude terminalinde yapılandırılmış transcript,
/// diğerlerinde ekranın (scrollback dahil) düz metni.
public enum RemoteTerminalReading: Sendable, Equatable {
    case transcript([ChatMessage])
    case screen(String)
}

/// Uzak Claude terminalinin chat akışının bir olayı — telefonun chat hattıyla aynı
/// frame'ler (karar 88/104/105/130): `chat`, `chat_append`, `chat_status`, `prompt`.
public enum RemoteChatEvent: Sendable, Equatable {
    /// Tam liste; `hasEarlier` ise frame bütçesi yüzünden eski mesajlar düştü.
    case snapshot([ChatMessage], hasEarlier: Bool)
    /// Kuyruğa gelen mesajlar (kimliğe göre güncellenir). `afterId` varsa fark
    /// aboneliğinin cevabıdır: listede o kimlikten sonrası bunlarla değişir.
    case append([ChatMessage], afterId: String?)
    case status(ChatTurnStatus)
    case prompt(ChatPrompt)
}

/// İzin / soru kartının cevabı.
public enum RemotePromptAnswer: Sendable, Equatable {
    /// Onay kartında seçilen seçenek.
    case option(String)
    /// Soru kartında soru başına seçilen indeksler + serbest metin.
    case selections([RemotePromptSelection])
}

public struct RemotePromptSelection: Sendable, Equatable {
    public var indices: [Int]
    public var other: String?

    public init(indices: [Int], other: String? = nil) {
        self.indices = indices
        self.other = other
    }
}

public enum RemoteControllerEvent: Sendable, Equatable {
    case directoryStateChanged(RemoteConnectionState)
    case hubsChanged([RemoteHubInfo])
    case linkChanged(hubId: String, RemoteHubLinkState)
    case snapshotChanged(hubId: String, RemoteHubSnapshot)
}

public enum RemoteControllerError: Error, Equatable, Sendable {
    case notConnected
    case timedOut
    case failed(String)
}
