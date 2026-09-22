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

    /// Launch komutunun ilk token'ından sağlayıcı çıkarımı (`claude …` /
    /// `codex …`); başka komut ya da `nil` → `nil` (düz shell).
    ///
    /// `&&` zinciri varsa SON parçaya bakılır: DeepSeek terminali
    /// `source "…/deepseek.env" && claude` ile açılır (karar 54) ve kartın
    /// kimliği yine Claude'dur — çalışan CLI gerçekten claude'dur.
    public static func detect(launchCommand: String?) -> AgentProvider? {
        guard let command = launchCommand else { return nil }
        let lastStage = command.components(separatedBy: "&&").last ?? command
        guard let first = lastStage.split(whereSeparator: \.isWhitespace).first else { return nil }
        return AgentProvider(rawValue: String(first))
    }
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
    /// Codex thread learned from the provider hook. Fresh Codex sessions do
    /// not expose this at launch time, so it becomes available asynchronously.
    public var codexSessionID: String?
    /// CODEX_HOME used to launch this thread. Resume must stay on this home so
    /// account switching cannot point the thread lookup at another account.
    public let codexHome: String?
    /// Terminalde şu an hangi ajan koşuyor (karar 45): launch komutu, OSC/çıktı
    /// çıkarımı ve hook olaylarından türetilir; ajan çıkınca (`SessionEnd`)
    /// `nil`e döner = düz shell. Kart header'ındaki kimlik ikonunun kaynağı.
    public var provider: AgentProvider?
    /// Son durum değişiminin zamanı (karar 51): sidebar ajan satırındaki
    /// "9m / 2h" etiketi buradan türer; hiç değişmediyse `createdAt` geçer.
    public var statusChangedAt: Date?

    public init(
        id: TerminalID,
        name: String,
        repoPath: String,
        createdAt: Date,
        task: String? = nil,
        oscTitle: String? = nil,
        status: TerminalStatus = .idle,
        claudeSessionID: String? = nil,
        codexSessionID: String? = nil,
        codexHome: String? = nil,
        provider: AgentProvider? = nil,
        statusChangedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.createdAt = createdAt
        self.task = task
        self.oscTitle = oscTitle
        self.status = status
        self.claudeSessionID = claudeSessionID
        self.codexSessionID = codexSessionID
        self.codexHome = codexHome
        self.provider = provider
        self.statusChangedAt = statusChangedAt
    }

    /// Sidebar'daki göreli zaman kaynağı: son durum değişimi, yoksa doğum anı.
    public var lastActivityAt: Date { statusChangedAt ?? createdAt }

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
    /// Terminaldeki ajan kimliği değişti (karar 45): `nil` = düz shell.
    case providerChanged(TerminalID, AgentProvider?)
    /// Karar 90: Codex lider hook'u thread kimliğini bildirdi. Resume
    /// checkpoint'i bunu görünce `ui-state.json`'ı yeniler — kimlik spawn'da
    /// bilinmediği için `.spawned` tek başına yetmez.
    case codexSessionIDChanged(TerminalID, String)
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
    /// Karar 57: terminalde bir link/path tıklandı. Hedefin çözümlenmesi
    /// (URL / workspace / dizin / dosya) ve eylemler store katmanındadır.
    case linkActivated(TerminalLinkActivation)
}
