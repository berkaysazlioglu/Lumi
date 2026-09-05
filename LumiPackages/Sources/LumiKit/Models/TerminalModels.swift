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

/// 6 durumlu, provider-agnostic terminal durumu.
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

/// AI sağlayıcısı (config seviyesi).
public enum AgentProvider: String, Sendable, Codable, Equatable, CaseIterable {
    case claude
    case codex

    /// Yeni provider terminalinde spawn sonrası enjekte edilen CLI komutu
    /// (önce shell açılır, sonra komut yazılır).
    public var launchCommand: String { rawValue }
}

/// Terminal metadata'sı — UI/state katmanının gördüğü tek model.
/// Ham çıktı ASLA burada taşınmaz (design/00 Ek A §A.1-1); ekran modeli emülatörde yaşar.
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

    /// Kullanıcıya gösterilen başlık — TEK kaynak (refactor 6.7).
    /// Öncelik: emülatörün OSC başlığı > spawn görevi > üretilen ad.
    /// Kart header'ı, maximize header'ı, chip şeridi ve session listesi
    /// bu türevi paylaşır (önceden 5 ayrı kopyaydı).
    public var displayTitle: String { oscTitle ?? task ?? name }
}

/// Terminal servisinin yayınladığı yaşam döngüsü event'leri.
/// Ham çıktı event değildir — PTY→emülatör hattında LumiTerminal içinde akar.
public enum TerminalEvent: Sendable, Equatable {
    case spawned(TerminalMeta)
    case exited(TerminalID, code: Int32)
    case statusChanged(TerminalID, TerminalStatus)
    case titleChanged(TerminalID, String)
    /// "Karar bekliyor" (izin promptu) sinyali — status'ten ayrı.
    /// Prompt kuyruğu bunu görünce duraklar; renk/durum değişmez.
    case awaitingDecisionChanged(TerminalID, Bool)
    case bell(TerminalID)
    /// PTY'ye yazım kalıcı olarak başarısız (EPIPE/EIO — child öldü).
    /// Karar 5: sessiz yutma yok; store toast gösterir.
    case writeFailed(TerminalID, errno: Int32)
    /// Feed akışı durdu (in-flight byte var ama emülatör 2 sn'dir beslenemedi)
    /// ya da düzeldi — design/00 Ek A §A.2-10 donma gözetimi. Ephemeral sinyal:
    /// `TerminalMeta` formatına YAZILMAZ (karar 9), store'da geçici set'te durur.
    case stalled(TerminalID, Bool)
    /// Terminal NSView'ı first responder oldu (karta tıklama). Store odağı
    /// buna göre senkronlar — composition root'ta callback köprüsü yerine
    /// diğer tüm terminal sinyalleriyle aynı kanaldan akar (Faz 3.7).
    case viewFocused(TerminalID)
}
