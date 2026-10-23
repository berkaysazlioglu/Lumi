import Foundation
import LumiKit
import Observation

/// Orchestrator'ın ne yaptığını gösteren ışık süzmeleri (karar 126).
///
/// Yalnız bir görsel sinyaldir: orchestrator bir terminale prompt gönderince
/// ya da terminal açınca ışık orchestrator'dan hedefe, ağacı / terminalleri
/// okuyunca ya da izlenen terminalin özeti ona ulaşınca hedeften
/// orchestrator'a eğimli bir yolla uçar. Uçtuğu ya da indiği yerde hiçbir
/// şey değişmez — bu tip yalnız "hangi uçuş, ne zaman" bilgisini tutar;
/// konumları ve çizimi arayüz çözer.
@Observable
@MainActor
public final class OrchestratorFlights {
    public enum Direction: Equatable, Sendable {
        /// Orchestrator → hedef (prompt gönderme, terminal açma).
        case outbound
        /// Hedef → orchestrator (okuma, izlenen terminalin özeti).
        case inbound
    }

    /// Uçuşun orchestrator dışındaki ucu. Arayüz bunu en görünür karşılığına
    /// çözer (terminal kartı → Projects'teki ajan satırı → checkout → proje).
    public enum Endpoint: Hashable, Sendable {
        case terminal(TerminalID)
        /// Checkout ya da `Other` dizini (karar 108).
        case checkout(String)
        case project(String)
    }

    public struct Flight: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let direction: Direction
        public let endpoint: Endpoint
        public let startsAt: Date

        public init(id: UUID = UUID(), direction: Direction, endpoint: Endpoint, startsAt: Date) {
            self.id = id
            self.direction = direction
            self.endpoint = endpoint
            self.startsAt = startsAt
        }

        public var endsAt: Date { startsAt.addingTimeInterval(OrchestratorFlights.duration) }

        /// 0…1 arası ilerleme; başlamadıysa negatif, bittiyse 1'den büyük.
        public func progress(at date: Date) -> Double {
            date.timeIntervalSince(startsAt) / OrchestratorFlights.duration
        }
    }

    /// Tek uçuşun süresi (saniye).
    nonisolated public static let duration: TimeInterval = 0.9
    /// Aynı anda kalkan uçuşlar arasındaki aralık — çoklu okuma bir dizi gibi akar.
    public static let stagger: TimeInterval = 0.07
    /// Tek eylemin kaldırdığı en fazla uçuş (ör. 30 projeli `list_projects`).
    public static let maxPerLaunch = 8
    /// Aynı anda havada kalabilecek en fazla uçuş.
    public static let maxActive = 24

    public private(set) var active: [Flight] = []

    @ObservationIgnored private let now: @MainActor () -> Date

    public init(now: @escaping @MainActor () -> Date = { Date() }) {
        self.now = now
    }

    /// Uçuşları kaldırır; tekrarlanan uçlar bir kez uçar. `delay` yeni açılan
    /// terminalin kartı çizilsin diye kalkışı erteler.
    public func launch(_ direction: Direction, _ endpoints: [Endpoint], delay: TimeInterval = 0) {
        var seen = Set<Endpoint>()
        let unique = endpoints.filter { seen.insert($0).inserted }.prefix(Self.maxPerLaunch)
        guard !unique.isEmpty else { return }
        let start = now().addingTimeInterval(delay)
        let flights = unique.enumerated().map { index, endpoint in
            Flight(
                direction: direction,
                endpoint: endpoint,
                startsAt: start.addingTimeInterval(Double(index) * Self.stagger)
            )
        }
        expire()
        active = Array((active + flights).suffix(Self.maxActive))
        scheduleExpiry(after: flights.last?.endsAt ?? start)
    }

    /// Bitmiş uçuşları düşürür (zamanlayıcı ve testler sürer).
    public func expire() {
        let date = now()
        let remaining = active.filter { $0.endsAt > date }
        if remaining.count != active.count { active = remaining }
    }

    private func scheduleExpiry(after date: Date) {
        let wait = max(date.timeIntervalSince(now()), 0) + Self.expiryGrace
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            self?.expire()
        }
    }

    /// Son karenin çizilmesine pay.
    private static let expiryGrace: TimeInterval = 0.05
}
