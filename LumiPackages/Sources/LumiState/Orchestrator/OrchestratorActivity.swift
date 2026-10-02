import Foundation
import LumiKit
import Observation

/// Bir ajan terminalinden gelen olay (karar 103 Faz 4): turn bitti, karar
/// bekliyor ya da hatayla durdu — özetiyle.
public struct OrchestratorEvent: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// İzlenen terminal bir turn'ü kapattı.
        case finished
        /// İzin/soru promptunda bekliyor (karar bekleme).
        case needsDecision
        /// Çalışırken hata durumuna düştü.
        case failed
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

/// Orchestrator'ın Activity paneli (karar 103 Faz 4). Olaylar yalnız
/// bellektedir (en yeni önce, `capacity` kadar).
///
/// İki ayrı "okundu" kavramı vardır:
/// - **Kullanıcı**: popup açıkken görülen olaylar okunmuş sayılır (top bar noktası).
/// - **Model**: olaylar model turu AÇMAZ; kullanıcının bir sonraki mesajına
///   `<lumi-activity>` notu olarak iliştirilir (`consumeContextNote`) — böylece
///   orchestrator "az önce ne bitti?" sorusunu araç çağırmadan bilir.
@Observable
@MainActor
public final class OrchestratorActivityFeed {
    public static let capacity = 50

    public private(set) var events: [OrchestratorEvent] = []
    public private(set) var unreadCount = 0

    /// Modele henüz bildirilmemiş olaylar (eskiden yeniye).
    @ObservationIgnored private var unreported: [OrchestratorEvent] = []

    public init() {}

    public func append(_ event: OrchestratorEvent) {
        // Aynı terminalin eski kartı yenisiyle değişir — liste terminal başına tek durum gösterir.
        events.removeAll { $0.terminalID == event.terminalID }
        events.insert(event, at: 0)
        if events.count > Self.capacity { events.removeLast(events.count - Self.capacity) }
        unreported.removeAll { $0.terminalID == event.terminalID }
        unreported.append(event)
        unreadCount += 1
    }

    public func markAllRead() {
        unreadCount = 0
    }

    public func dismiss(_ id: UUID) {
        events.removeAll { $0.id == id }
    }

    /// Bir sonraki kullanıcı mesajına iliştirilecek not; yoksa nil. Çağrı
    /// listeyi boşaltır (her olay modele bir kez gider).
    public func consumeContextNote(now: Date = Date()) -> String? {
        guard !unreported.isEmpty else { return nil }
        defer { unreported.removeAll() }
        return OrchestratorActivityNote.make(unreported, now: now)
    }
}

/// `<lumi-activity>` notunun biçimi. Not kullanıcı mesajıyla AYNI turda
/// gider ama kullanıcının yazdığı değildir: balonda gizlenir (`strip`).
public enum OrchestratorActivityNote {
    public static let open = "<lumi-activity>"
    public static let close = "</lumi-activity>"

    static func make(_ events: [OrchestratorEvent], now: Date) -> String {
        let lines = events.map { event in
            let tag: String
            switch event.kind {
            case .finished: tag = event.needsUser ? "finished, asks the user" : "finished"
            case .needsDecision: tag = "awaiting decision"
            case .failed: tag = "error"
            }
            let summary = event.summary.split(whereSeparator: \.isNewline).joined(separator: " ")
            return "- [\(tag)] \"\(event.terminalTitle)\" (\(event.location), id \(event.terminalID)), "
                + "\(OrchestratorToolFormat.ago(event.at, now: now)): \(summary)"
        }
        return ([open, "Terminal updates from Lumi since the user's last message (not typed by the user):"]
            + lines + [close]).joined(separator: "\n")
    }

    /// Kullanıcı balonunda gösterilecek metin: baştaki not atılır.
    public static func strip(_ text: String) -> String {
        guard text.hasPrefix(open), let end = text.range(of: close) else { return text }
        return String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Notu kullanıcı mesajının başına ekler.
    public static func attach(_ note: String?, to message: String) -> String {
        guard let note else { return message }
        return note + "\n\n" + message
    }
}
