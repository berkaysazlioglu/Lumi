import Foundation
import LumiKit
import Observation

/// Bir ajan terminalinden gelen olay (karar 114 Faz 4): turn bitti, karar
/// bekliyor ya da hatayla durdu — özetiyle.
public struct OrchestratorEvent: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// İzlenen terminal bir turn'ü kapattı.
        case finished
        /// İzin/soru promptunda bekliyor (karar bekleme).
        case needsDecision
        /// Çalışırken hata durumuna düştü.
        case failed
        /// Turn bitmeden kesildi (Esc/Ctrl+C ya da telefondan Stop) — main'in
        /// `TerminalEvent.interruptInferred` sinyali.
        case interrupted
    }

    public let id: UUID
    public let terminalID: TerminalID
    public let terminalTitle: String
    /// proje · checkout · dal.
    public let location: String
    public let kind: Kind
    public let summary: String
    public let needsUser: Bool
    public let at: Date

    public init(
        id: UUID = UUID(), terminalID: TerminalID, terminalTitle: String, location: String,
        kind: Kind, summary: String, needsUser: Bool, at: Date
    ) {
        self.id = id
        self.terminalID = terminalID
        self.terminalTitle = terminalTitle
        self.location = location
        self.kind = kind
        self.summary = summary
        self.needsUser = needsUser
        self.at = at
    }
}

/// Haiku özetlerinin toplandığı yer (karar 114 Faz 4, karar 123): Activity
/// paneli ve orchestrator monitörünün kaynağı. Olaylar yalnız bellektedir
/// (en yeni önce, `capacity` kadar).
///
/// İki ayrı "okundu" kavramı vardır:
/// - **Kullanıcı**: popup açıkken görülen olaylar okunmuş sayılır (top bar noktası).
/// - **Model**: `OrchestratorActivityMonitor` her yeni özette raporlanmamış
///   olayları alır (`takeUnreported`) ve `codex queue` ile orchestrator'a
///   bırakır; teslim edilemezse geri koyar (`returnUnreported`).
@Observable
@MainActor
public final class OrchestratorActivityFeed {
    public static let capacity = 50

    public private(set) var events: [OrchestratorEvent] = []
    public private(set) var unreadCount = 0

    /// Monitörün kancası: her yeni özet geldiğinde çağrılır.
    @ObservationIgnored public var onAppend: (@MainActor () -> Void)?
    /// Orchestrator'a henüz bildirilmemiş olaylar (eskiden yeniye).
    @ObservationIgnored private var unreported: [OrchestratorEvent] = []

    public init() {}

    public var hasUnreported: Bool { !unreported.isEmpty }

    public func append(_ event: OrchestratorEvent) {
        // Aynı terminalin eski kartı yenisiyle değişir — liste terminal başına tek durum gösterir.
        events.removeAll { $0.terminalID == event.terminalID }
        events.insert(event, at: 0)
        if events.count > Self.capacity { events.removeLast(events.count - Self.capacity) }
        unreported.removeAll { $0.terminalID == event.terminalID }
        unreported.append(event)
        unreadCount += 1
        onAppend?()
    }

    public func markAllRead() {
        unreadCount = 0
    }

    public func dismiss(_ id: UUID) {
        events.removeAll { $0.id == id }
    }

    /// Orchestrator'a gidecek olaylar; liste boşalır (her olay bir kez gider).
    public func takeUnreported() -> [OrchestratorEvent] {
        defer { unreported.removeAll() }
        return unreported
    }

    /// Teslim edilemeyen olaylar sıranın başına döner — bu arada aynı
    /// terminalden daha yenisi geldiyse eskisi düşer.
    public func returnUnreported(_ events: [OrchestratorEvent]) {
        let newer = Set(unreported.map(\.terminalID))
        unreported.insert(contentsOf: events.filter { !newer.contains($0.terminalID) }, at: 0)
    }
}

/// `<lumi-activity>` notunun biçimi (karar 123): monitör bunu `codex queue`
/// ile orchestrator'a bırakır; talimat (`OrchestratorPrompt`) notu Lumi'nin
/// yazdığı bir güncelleme olarak tanımlar.
public enum OrchestratorActivityNote {
    public static let open = OrchestratorPrompt.activityOpen
    public static let close = OrchestratorPrompt.activityClose

    public static func make(_ events: [OrchestratorEvent], now: Date) -> String {
        let lines = events.map { event in
            let tag: String
            switch event.kind {
            case .finished: tag = event.needsUser ? "finished, asks the user" : "finished"
            case .needsDecision: tag = "awaiting decision"
            case .failed: tag = "error"
            case .interrupted: tag = "interrupted"
            }
            let summary = event.summary.split(whereSeparator: \.isNewline).joined(separator: " ")
            return "- [\(tag)] \"\(event.terminalTitle)\" (\(event.location), id \(event.terminalID)), "
                + "\(OrchestratorToolFormat.ago(event.at, now: now)): \(summary)"
        }
        return ([open, "Update from Lumi's monitor on watched terminals (not typed by the user):"]
            + lines + [close]).joined(separator: "\n")
    }
}
